mod config;
mod onepassword;
mod pty;
mod tsh;

use std::{
    error::Error,
    sync::mpsc::{self, Sender},
    thread,
    time::Duration,
};

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use nucleo_matcher::{
    pattern::{CaseMatching, Normalization, Pattern},
    Config as MatcherConfig, Matcher, Utf32Str,
};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::{Modifier, Style, Stylize},
    text::{Line, Span},
    widgets::{Block, List, ListState, Paragraph},
    DefaultTerminal, Frame,
};
use tui_term::widget::PseudoTerminal;

use config::Config;
use onepassword::{Credentials, Prompt, PromptDetector};
use pty::{key_bytes, PtySession};
use tsh::{Node, Session};

/// Everything the main loop reacts to arrives through one channel.
pub enum Msg {
    Key(KeyEvent),
    Redraw,
    Output(usize, String),
    Exited(usize),
    Loaded(Result<(Session, Vec<Node>), String>),
    LoginReady(Result<Credentials, String>),
    Answer { id: usize, secret: Result<String, String>, notice: &'static str },
}

/// State of a `tsh login` tab that answers its own prompts from 1Password.
struct LoginState {
    creds: Option<Credentials>,
    detector: PromptDetector,
}

struct Tab {
    id: usize,
    title: String,
    pty: PtySession,
    login: Option<LoginState>,
}

struct App {
    tx: Sender<Msg>,
    config: Config,
    notice: Option<String>,
    nodes: Vec<Node>,
    session: Session,
    loading: bool,
    error: Option<String>,
    query: String,
    visible: Vec<usize>,
    list: ListState,
    matcher: Matcher,
    tabs: Vec<Tab>,
    /// 0 is the host picker, n > 0 is tabs[n - 1].
    active: usize,
    /// Waiting for the second key of a Ctrl-G command.
    prefix: bool,
    next_id: usize,
    content: (u16, u16),
}

impl App {
    fn new(tx: Sender<Msg>, config: Config) -> Self {
        Self {
            tx,
            config,
            notice: None,
            nodes: Vec::new(),
            session: Session::default(),
            loading: false,
            error: None,
            query: String::new(),
            visible: Vec::new(),
            list: ListState::default(),
            matcher: Matcher::new(MatcherConfig::DEFAULT),
            tabs: Vec::new(),
            active: 0,
            prefix: false,
            next_id: 0,
            content: (24, 80),
        }
    }

    fn reload(&mut self) {
        self.loading = true;
        let (tx, proxy) = (self.tx.clone(), self.config.proxy.clone());
        thread::spawn(move || {
            let result = tsh::load_session()
                .and_then(|s| tsh::load_nodes(proxy.as_deref()).map(|n| (s, n)));
            let _ = tx.send(Msg::Loaded(result));
        });
    }

    fn refilter(&mut self) {
        if self.query.trim().is_empty() {
            self.visible = (0..self.nodes.len()).collect();
        } else {
            let pattern = Pattern::parse(&self.query, CaseMatching::Ignore, Normalization::Smart);
            let mut buf = Vec::new();
            let mut scored: Vec<(usize, u32)> = self
                .nodes
                .iter()
                .enumerate()
                .filter_map(|(i, n)| {
                    let hay = Utf32Str::new(&n.haystack, &mut buf);
                    pattern.score(hay, &mut self.matcher).map(|s| (i, s))
                })
                .collect();
            scored.sort_by(|a, b| b.1.cmp(&a.1));
            self.visible = scored.into_iter().map(|(i, _)| i).collect();
        }
        self.list.select(if self.visible.is_empty() { None } else { Some(0) });
    }

    fn move_selection(&mut self, delta: isize) {
        if self.visible.is_empty() {
            return;
        }
        let last = self.visible.len() as isize - 1;
        let current = self.list.selected().unwrap_or(0) as isize;
        self.list.select(Some((current + delta).clamp(0, last) as usize));
    }

    fn selected(&self) -> Option<&Node> {
        self.list.selected().and_then(|i| self.visible.get(i)).map(|&i| &self.nodes[i])
    }

    /// Label `user` if the session allows it, otherwise the first allowed login.
    fn login_for(&self, node: &Node) -> Option<String> {
        let allowed = &self.session.logins;
        node.labels
            .get("user")
            .filter(|u| !u.is_empty() && (allowed.is_empty() || allowed.contains(u)))
            .or_else(|| allowed.first())
            .cloned()
    }

    fn open_session(&mut self) {
        let Some(node) = self.selected() else { return };
        let title = node.hostname.clone();
        let target = match self.login_for(node) {
            Some(login) => format!("{login}@{title}"),
            None => title.clone(),
        };
        let id = self.next_id;
        self.next_id += 1;
        match PtySession::spawn(id, "tsh", &["ssh", &target], self.content, self.tx.clone()) {
            Ok(pty) => {
                self.tabs.push(Tab { id, title, pty, login: None });
                self.active = self.tabs.len();
                self.error = None;
            }
            Err(e) => self.error = Some(e),
        }
    }

    fn close_active(&mut self) {
        if self.active == 0 {
            return;
        }
        self.tabs.remove(self.active - 1).pty.kill();
        self.active = self.active.min(self.tabs.len());
    }

    fn resize(&mut self, rows: u16, cols: u16) {
        self.content = (rows.saturating_sub(1), cols);
        for tab in &mut self.tabs {
            tab.pty.resize(self.content.0, self.content.1);
        }
    }

    /// Returns true when the app should quit.
    fn handle(&mut self, msg: Msg) -> bool {
        match msg {
            Msg::Key(key) => return self.on_key(key),
            Msg::Redraw => {}
            Msg::Output(id, text) => self.on_output(id, &text),
            Msg::Exited(id) => self.on_exit(id),
            Msg::LoginReady(result) => match result {
                Ok(creds) => self.open_login(Some(creds)),
                Err(e) => {
                    self.notice = Some(format!("1Password: {e} Log in manually."));
                    self.open_login(None);
                }
            },
            Msg::Answer { id, secret, notice } => match secret {
                Ok(secret) => {
                    if let Some(tab) = self.tabs.iter_mut().find(|t| t.id == id && !t.pty.exited) {
                        tab.pty.write(format!("{secret}\r").as_bytes());
                        self.notice = Some(notice.into());
                    }
                }
                Err(e) => self.notice = Some(format!("1Password: {e} Enter it manually.")),
            },
            Msg::Loaded(result) => {
                self.loading = false;
                match result {
                    Ok((session, nodes)) => {
                        (self.session, self.nodes, self.error) = (session, nodes, None);
                        self.refilter();
                    }
                    Err(e) => self.error = Some(e),
                }
            }
        }
        false
    }

    fn on_exit(&mut self, id: usize) {
        let Some(index) = self.tabs.iter().position(|t| t.id == id) else { return };
        self.tabs[index].pty.reap();
        // A successful login closes itself and refreshes the host list.
        if self.tabs[index].login.is_some() && self.tabs[index].pty.exit_ok == Some(true) {
            self.tabs.remove(index);
            self.active = 0;
            self.notice = None;
            self.reload();
        }
    }

    fn on_output(&mut self, id: usize, text: &str) {
        let Some(tab) = self.tabs.iter_mut().find(|t| t.id == id) else { return };
        let Some(login) = tab.login.as_mut() else { return };
        let (Some(creds), Some(prompt)) = (&login.creds, login.detector.consume(text)) else { return };

        let (tx, config, password) = (self.tx.clone(), self.config.clone(), creds.password.clone());
        thread::spawn(move || {
            // Read the OTP only when tsh asks so it is as fresh as possible.
            let (secret, notice) = match prompt {
                Prompt::Password => (Ok(password), "Password filled from 1Password"),
                Prompt::OneTimePassword => {
                    (onepassword::load_otp(&config), "Password and OTP filled from 1Password")
                }
            };
            // Give tsh a moment to switch the terminal to no-echo mode.
            thread::sleep(Duration::from_millis(250));
            let _ = tx.send(Msg::Answer { id, secret, notice });
        });
    }

    fn start_login(&mut self) {
        if let Some(i) = self.tabs.iter().position(|t| t.login.is_some() && !t.pty.exited) {
            self.active = i + 1;
        } else if self.config.op_item.is_some() {
            self.notice = Some("Reading credentials from 1Password…".into());
            let (tx, config) = (self.tx.clone(), self.config.clone());
            thread::spawn(move || {
                let _ = tx.send(Msg::LoginReady(onepassword::load_credentials(&config)));
            });
        } else {
            self.open_login(None);
        }
    }

    fn open_login(&mut self, creds: Option<Credentials>) {
        let mut args = vec!["login".to_string()];
        if let Some(proxy) = &self.config.proxy {
            args.push(format!("--proxy={proxy}"));
        }
        let user = self.config.user.clone().or_else(|| creds.as_ref()?.username.clone());
        if let Some(user) = user {
            args.push(format!("--user={user}"));
        }

        let id = self.next_id;
        self.next_id += 1;
        let args: Vec<&str> = args.iter().map(String::as_str).collect();
        match PtySession::spawn(id, "tsh", &args, self.content, self.tx.clone()) {
            Ok(pty) => {
                let login = LoginState { creds, detector: PromptDetector::default() };
                self.tabs.push(Tab { id, title: "login".into(), pty, login: Some(login) });
                self.active = self.tabs.len();
            }
            Err(e) => self.error = Some(e),
        }
    }

    fn on_key(&mut self, key: KeyEvent) -> bool {
        let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
        if std::mem::take(&mut self.prefix) {
            return self.on_prefix(key);
        }
        if ctrl && key.code == KeyCode::Char('g') {
            self.prefix = true;
            return false;
        }
        if self.active == 0 {
            return self.on_picker_key(key, ctrl);
        }

        let tab = &mut self.tabs[self.active - 1];
        if tab.pty.exited {
            self.close_active();
        } else if key.modifiers.contains(KeyModifiers::SHIFT)
            && matches!(key.code, KeyCode::PageUp | KeyCode::PageDown)
        {
            let page = self.content.0 as isize / 2;
            tab.pty.scroll(if key.code == KeyCode::PageUp { page } else { -page });
        } else if let Some(bytes) = key_bytes(key, tab.pty.app_cursor()) {
            tab.pty.reset_scroll();
            tab.pty.write(&bytes);
        }
        false
    }

    fn on_prefix(&mut self, key: KeyEvent) -> bool {
        let total = self.tabs.len() + 1;
        match key.code {
            KeyCode::Char('n') | KeyCode::Right => self.active = (self.active + 1) % total,
            KeyCode::Char('p') | KeyCode::Left => self.active = (self.active + total - 1) % total,
            KeyCode::Char('h') => self.active = 0,
            KeyCode::Char('w') => self.close_active(),
            KeyCode::Char('q') => return true,
            KeyCode::Char(c @ '1'..='9') => {
                let target = c as usize - '0' as usize;
                if target <= self.tabs.len() {
                    self.active = target;
                }
            }
            // Ctrl-G Ctrl-G sends a literal Ctrl-G to the remote shell.
            KeyCode::Char('g') if self.active > 0 => self.tabs[self.active - 1].pty.write(&[7]),
            _ => {}
        }
        false
    }

    fn on_picker_key(&mut self, key: KeyEvent, ctrl: bool) -> bool {
        match key.code {
            KeyCode::Esc => return self.leave_picker(),
            KeyCode::Char('c') if ctrl => return self.leave_picker(),
            KeyCode::Up => self.move_selection(-1),
            KeyCode::Down => self.move_selection(1),
            KeyCode::Char('p') if ctrl => self.move_selection(-1),
            KeyCode::Char('n') if ctrl => self.move_selection(1),
            KeyCode::Char('r') if ctrl => self.reload(),
            KeyCode::Char('l') if ctrl => self.start_login(),
            KeyCode::Char('u') if ctrl => {
                self.query.clear();
                self.refilter();
            }
            KeyCode::Backspace => {
                self.query.pop();
                self.refilter();
            }
            KeyCode::Char(c) if !ctrl => {
                self.query.push(c);
                self.refilter();
            }
            KeyCode::Enter => self.open_session(),
            _ => {}
        }
        false
    }

    /// Esc on the picker quits when nothing is open, otherwise returns to the last session.
    fn leave_picker(&mut self) -> bool {
        self.active = self.tabs.len();
        self.tabs.is_empty()
    }

    fn draw(&mut self, frame: &mut Frame) {
        let [bar, content] =
            Layout::vertical([Constraint::Length(1), Constraint::Min(1)]).areas(frame.area());
        frame.render_widget(self.tab_bar(), bar);

        if self.active == 0 {
            self.draw_picker(frame, content);
        } else {
            let parser = self.tabs[self.active - 1].pty.parser.lock().unwrap();
            frame.render_widget(PseudoTerminal::new(parser.screen()), content);
        }
    }

    fn tab_bar(&self) -> Line<'static> {
        let style = |on: bool| {
            if on { Style::new().add_modifier(Modifier::REVERSED) } else { Style::new() }
        };
        let mut spans = vec![Span::styled(" Hosts ", style(self.active == 0))];
        for (i, tab) in self.tabs.iter().enumerate() {
            let mark = if tab.pty.exited { " ✗" } else { "" };
            let label = format!(" {} {}{} ", i + 1, tab.title, mark);
            spans.push(Span::styled(label, style(self.active == i + 1)));
        }
        match (&self.notice, self.prefix) {
            (_, true) => spans.push(
                Span::raw("  ^G… n/p switch  1-9 jump  h hosts  w close  q quit  g literal ^G").dark_gray(),
            ),
            (Some(notice), _) => spans.push(Span::raw(format!("  {notice}")).cyan()),
            _ => spans.push(Span::raw("  ^G for commands").dark_gray()),
        }
        Line::from(spans)
    }

    fn draw_picker(&mut self, frame: &mut Frame, area: Rect) {
        let [input, body, status] = Layout::vertical([
            Constraint::Length(3),
            Constraint::Min(1),
            Constraint::Length(1),
        ])
        .areas(area);

        frame.render_widget(
            Paragraph::new(format!("> {}", self.query)).block(Block::bordered().title("Filter")),
            input,
        );
        frame.set_cursor_position((input.x + 3 + self.query.chars().count() as u16, input.y + 1));

        let width = self.visible.iter().map(|&i| self.nodes[i].hostname.len()).max().unwrap_or(0);
        let items: Vec<Line> = self
            .visible
            .iter()
            .map(|&i| {
                let n = &self.nodes[i];
                let labels = n.labels.iter().map(|(k, v)| format!("{k}={v}")).collect::<Vec<_>>();
                Line::from(vec![
                    Span::raw(format!("{:width$}  ", n.hostname)),
                    Span::raw(labels.join(" ")).dark_gray(),
                ])
            })
            .collect();
        let title = if self.loading {
            "Hosts (loading…)".to_string()
        } else {
            format!("Hosts ({}/{})", self.visible.len(), self.nodes.len())
        };
        frame.render_stateful_widget(
            List::new(items)
                .block(Block::bordered().title(title))
                .highlight_style(Style::new().add_modifier(Modifier::REVERSED)),
            body,
            &mut self.list,
        );

        let line = match &self.error {
            Some(e) => Line::from(format!("{e}  (ctrl-l to log in)")).red(),
            None => Line::from(format!(
                "{}  |  enter open  ctrl-l login  ctrl-r reload  esc back",
                self.session.summary
            ))
            .dark_gray(),
        };
        frame.render_widget(Paragraph::new(line), status);
    }

    fn shutdown(&mut self) {
        for tab in &mut self.tabs {
            tab.pty.kill();
        }
    }
}

fn run(terminal: &mut DefaultTerminal, app: &mut App, rx: mpsc::Receiver<Msg>) -> Result<(), Box<dyn Error>> {
    app.reload();
    loop {
        let size = terminal.size()?;
        app.resize(size.height, size.width);
        terminal.draw(|f| app.draw(f))?;

        let mut quit = app.handle(rx.recv()?);
        while !quit {
            match rx.try_recv() {
                Ok(msg) => quit = app.handle(msg),
                Err(_) => break,
            }
        }
        if quit {
            return Ok(());
        }
    }
}

fn main() -> Result<(), Box<dyn Error>> {
    let (tx, rx) = mpsc::channel();

    let input_tx = tx.clone();
    thread::spawn(move || loop {
        let msg = match event::read() {
            Ok(Event::Key(key)) if key.kind == KeyEventKind::Press => Msg::Key(key),
            Ok(Event::Resize(..)) => Msg::Redraw,
            Ok(_) => continue,
            Err(_) => break,
        };
        if input_tx.send(msg).is_err() {
            break;
        }
    });

    let mut app = App::new(tx, Config::load());
    let mut terminal = ratatui::init();
    let result = run(&mut terminal, &mut app, rx);
    ratatui::restore();
    app.shutdown();
    result
}

#[cfg(test)]
mod tests {
    use std::{collections::BTreeMap, time::Duration};

    use super::*;

    #[test]
    fn filters_and_resolves_login() {
        let mut app = App::new(mpsc::channel().0, Config::default());
        app.nodes = vec![
            Node {
                hostname: "agrario.db01".into(),
                labels: [("user".to_string(), "ubuntu".to_string())].into(),
                haystack: "agrario.db01 user ubuntu".into(),
            },
            Node { hostname: "agrario.m02".into(), labels: BTreeMap::new(), haystack: "agrario.m02".into() },
        ];
        app.session.logins = vec!["ubuntu".into(), "root".into()];
        app.query = "db01".into();
        app.refilter();
        assert_eq!(app.visible, vec![0]);
        assert_eq!(app.login_for(&app.nodes[0]).as_deref(), Some("ubuntu"));
        assert_eq!(app.login_for(&app.nodes[1]).as_deref(), Some("ubuntu"));
    }

    #[test]
    fn pty_output_reaches_the_screen() {
        let (tx, rx) = mpsc::channel();
        let pty = PtySession::spawn(7, "echo", &["hello"], (5, 20), tx).unwrap();
        loop {
            if let Msg::Exited(7) = rx.recv_timeout(Duration::from_secs(5)).unwrap() {
                break;
            }
        }
        assert!(pty.parser.lock().unwrap().screen().contents().contains("hello"));
    }
}
