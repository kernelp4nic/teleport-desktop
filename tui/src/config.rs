use std::{env, fs, path::PathBuf};

/// Settings from `~/.config/teleport-tui/config` (`key = value` lines), overridden by `--key=value` flags.
#[derive(Default, Clone)]
pub struct Config {
    pub proxy: Option<String>,
    pub user: Option<String>,
    pub op_item: Option<String>,
    pub op_vault: Option<String>,
    pub op_account: Option<String>,
}

impl Config {
    pub fn load() -> Self {
        let mut config = Self::default();
        if let Some(text) = config_path().and_then(|p| fs::read_to_string(p).ok()) {
            for (key, value) in text.lines().filter_map(|l| l.split_once('=')) {
                config.set(key.trim(), value.trim().trim_matches('"'));
            }
        }
        for arg in env::args().skip(1) {
            if let Some((key, value)) = arg.strip_prefix("--").and_then(|a| a.split_once('=')) {
                config.set(key, value);
            }
        }
        config
    }

    /// Setting keys in the order the settings screen shows them.
    pub const KEYS: [&'static str; 5] = ["proxy", "user", "op-item", "op-vault", "op-account"];

    pub fn get(&self, key: &str) -> &str {
        let value = match key {
            "proxy" => &self.proxy,
            "user" => &self.user,
            "op-item" => &self.op_item,
            "op-vault" => &self.op_vault,
            "op-account" => &self.op_account,
            _ => &None,
        };
        value.as_deref().unwrap_or("")
    }

    /// Writes every setting to the config file, creating it if needed.
    pub fn save(&self) -> Result<(), String> {
        let path = config_path().ok_or("Could not locate the config directory.")?;
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        let text: String = Self::KEYS
            .iter()
            .filter(|k| !self.get(k).is_empty())
            .map(|k| format!("{k} = {}\n", self.get(k)))
            .collect();
        fs::write(path, text).map_err(|e| e.to_string())
    }

    pub fn set(&mut self, key: &str, value: &str) {
        let value = Some(value.trim().to_string()).filter(|v| !v.is_empty());
        match key {
            "proxy" => self.proxy = value.map(normalize_proxy),
            "user" => self.user = value,
            "op-item" => self.op_item = value,
            "op-vault" => self.op_vault = value,
            "op-account" => self.op_account = value,
            _ => {}
        }
    }
}

fn config_path() -> Option<PathBuf> {
    let base = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
    Some(base.join("teleport-tui").join("config"))
}

fn normalize_proxy(value: String) -> String {
    let value = value.strip_prefix("https://").or_else(|| value.strip_prefix("http://")).unwrap_or(&value);
    value.trim_end_matches('/').to_string()
}
