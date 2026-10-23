use std::{
    io::{Read, Write},
    sync::{mpsc::Sender, Arc, Mutex},
    thread,
};

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use portable_pty::{native_pty_system, Child,CommandBuilder, MasterPty, PtySize};

use crate::Msg;

const SCROLLBACK: usize = 5000;

/// A child process on a pseudo-terminal whose output feeds a vt100 screen.
pub struct PtySession {
    pub parser: Arc<Mutex<vt100::Parser>>,
    pub exited: bool,
    pub exit_ok: Option<bool>,
    master: Box<dyn MasterPty + Send>,
    writer: Box<dyn Write + Send>,
    child: Box<dyn Child + Send + Sync>,
    size: (u16, u16),
}

impl PtySession {
    pub fn spawn(
        id: usize,
        program: &str,
        args: &[&str],
        (rows, cols): (u16, u16),
        tx: Sender<Msg>,
    ) -> Result<Self, String> {
        let pair = native_pty_system()
            .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
            .map_err(|e| e.to_string())?;
        let mut cmd = CommandBuilder::new(program);
        cmd.args(args);
        cmd.env("TERM", "xterm-256color");
        let child = pair.slave.spawn_command(cmd).map_err(|e| format!("{program}: {e}"))?;
        drop(pair.slave);

        let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
        let writer = pair.master.take_writer().map_err(|e| e.to_string())?;
        let parser = Arc::new(Mutex::new(vt100::Parser::new(rows, cols, SCROLLBACK)));

        let shared = Arc::clone(&parser);
        thread::spawn(move || {
            let mut buf = [0u8; 8192];
            while let Ok(n) = reader.read(&mut buf) {
                if n == 0 {
                    break;
                }
                shared.lock().unwrap().process(&buf[..n]);
                let _ = tx.send(Msg::Output(id, String::from_utf8_lossy(&buf[..n]).into_owned()));
            }
            let _ = tx.send(Msg::Exited(id));
        });

        Ok(Self { parser, exited: false, exit_ok: None, master: pair.master, writer, child, size: (rows, cols) })
    }

    pub fn resize(&mut self, rows: u16, cols: u16) {
        if self.size == (rows, cols) || rows == 0 || cols == 0 {
            return;
        }
        self.size = (rows, cols);
        let _ = self.master.resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 });
        self.parser.lock().unwrap().set_size(rows, cols);
    }

    pub fn write(&mut self, bytes: &[u8]) {
        let _ = self.writer.write_all(bytes).and_then(|_| self.writer.flush());
    }

    pub fn scroll(&self, delta: isize) {
        let mut parser = self.parser.lock().unwrap();
        let current = parser.screen().scrollback() as isize;
        parser.set_scrollback((current + delta).max(0) as usize);
    }

    pub fn reset_scroll(&self) {
        self.parser.lock().unwrap().set_scrollback(0);
    }

    pub fn app_cursor(&self) -> bool {
        self.parser.lock().unwrap().screen().application_cursor()
    }

    /// Called once the output stream ends: records how the child exited.
    pub fn reap(&mut self) {
        self.exited = true;
        self.exit_ok = self.child.wait().ok().map(|status| status.success());
    }

    pub fn kill(&mut self) {
        let _ = self.child.kill();
    }
}

/// Encode a key press the way an xterm would send it. None for keys we don't map.
pub fn key_bytes(key: KeyEvent, app_cursor: bool) -> Option<Vec<u8>> {
    let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
    let mut out = match key.code {
        KeyCode::Char(c) if ctrl && c.is_ascii_alphabetic() => {
            vec![c.to_ascii_lowercase() as u8 - b'a' + 1]
        }
        KeyCode::Char(c) if ctrl => match c {
            ' ' | '@' => vec![0],
            '[' => vec![27],
            '\\' => vec![28],
            ']' => vec![29],
            '^' => vec![30],
            '_' | '/' => vec![31],
            _ => return None,
        },
        KeyCode::Char(c) => c.to_string().into_bytes(),
        KeyCode::Enter => vec![b'\r'],
        KeyCode::Backspace => vec![0x7f],
        KeyCode::Tab => vec![b'\t'],
        KeyCode::BackTab => b"\x1b[Z".to_vec(),
        KeyCode::Esc => vec![0x1b],
        KeyCode::Up | KeyCode::Down | KeyCode::Right | KeyCode::Left => {
            let letter = match key.code {
                KeyCode::Up => b'A',
                KeyCode::Down => b'B',
                KeyCode::Right => b'C',
                _ => b'D',
            };
            vec![0x1b, if app_cursor { b'O' } else { b'[' }, letter]
        }
        KeyCode::Home => b"\x1b[H".to_vec(),
        KeyCode::End => b"\x1b[F".to_vec(),
        KeyCode::PageUp => b"\x1b[5~".to_vec(),
        KeyCode::PageDown => b"\x1b[6~".to_vec(),
        KeyCode::Delete => b"\x1b[3~".to_vec(),
        KeyCode::Insert => b"\x1b[2~".to_vec(),
        KeyCode::F(n @ 1..=4) => vec![0x1b, b'O', b'P' + n - 1],
        KeyCode::F(n @ 5..=12) => {
            let code = [15, 17, 18, 19, 20, 21, 23, 24][n as usize - 5];
            format!("\x1b[{code}~").into_bytes()
        }
        _ => return None,
    };
    if key.modifiers.contains(KeyModifiers::ALT) && matches!(key.code, KeyCode::Char(_)) {
        out.insert(0, 0x1b);
    }
    Some(out)
}
