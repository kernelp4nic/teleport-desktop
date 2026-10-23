use std::{io::ErrorKind, process::Command};

use serde_json::Value;

use crate::config::Config;

pub struct Credentials {
    pub username: Option<String>,
    pub password: String,
}

fn run(config: &Config, extra: &[&str]) -> Result<String, String> {
    let item = config.op_item.as_deref().ok_or("no 1Password item configured")?;
    let mut cmd = Command::new("op");
    cmd.args(["item", "get", item]);
    if let Some(vault) = &config.op_vault {
        cmd.arg(format!("--vault={vault}"));
    }
    if let Some(account) = &config.op_account {
        cmd.arg(format!("--account={account}"));
    }
    // With the 1Password app integration enabled, `op` prompts for Touch ID here.
    let out = cmd.args(extra).output().map_err(|e| match e.kind() {
        ErrorKind::NotFound => {
            "1Password CLI (op) was not found. Install it with `brew install 1password-cli`.".to_string()
        }
        _ => e.to_string(),
    })?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
        return Err(if stderr.is_empty() { format!("1Password CLI exited with {}.", out.status) } else { stderr });
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

pub fn load_credentials(config: &Config) -> Result<Credentials, String> {
    parse_credentials(&run(config, &["--format=json"])?)
}

pub fn load_otp(config: &Config) -> Result<String, String> {
    let output = run(config, &["--otp"])?;
    let code = output.trim();
    if code.is_empty() || !code.chars().all(|c| c.is_ascii_digit()) {
        return Err("The 1Password item has no one-time password.".into());
    }
    Ok(code.to_string())
}

pub fn parse_credentials(json: &str) -> Result<Credentials, String> {
    let item: Value = serde_json::from_str(json).map_err(|e| e.to_string())?;
    let fields = item["fields"].as_array().map(Vec::as_slice).unwrap_or_default();
    let value = |purpose: &str, label: &str| {
        let by_purpose = fields.iter().find(|f| f["purpose"] == purpose);
        let by_label = fields.iter().find(|f| f["label"].as_str().is_some_and(|l| l.to_lowercase() == label));
        by_purpose
            .or(by_label)
            .and_then(|f| f["value"].as_str())
            .filter(|v| !v.is_empty())
            .map(String::from)
    };
    Ok(Credentials {
        username: value("USERNAME", "username"),
        password: value("PASSWORD", "password").ok_or("The 1Password item has no password field.")?,
    })
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Prompt {
    Password,
    OneTimePassword,
}

/// Watches `tsh login` output and reports each credential prompt once, so a
/// rejected password falls back to manual entry instead of looping.
#[derive(Default)]
pub struct PromptDetector {
    buffer: String,
    answered: Vec<Prompt>,
}

impl PromptDetector {
    // "Enter your OTP token:", "Enter an OTP code from a device:" and
    // "Tap any security key or enter a code from a OTP device".
    const OTP_PHRASES: [&'static str; 3] = ["otp token", "otp code", "otp device"];

    pub fn consume(&mut self, text: &str) -> Option<Prompt> {
        self.buffer.push_str(&text.to_lowercase());
        if self.buffer.len() > 1024 {
            let mut start = self.buffer.len() - 1024;
            while !self.buffer.is_char_boundary(start) {
                start += 1;
            }
            self.buffer.drain(..start);
        }

        let prompt = if self.buffer.contains("enter password for teleport user") {
            Prompt::Password
        } else if Self::OTP_PHRASES.iter().any(|p| self.buffer.contains(p)) {
            Prompt::OneTimePassword
        } else {
            return None;
        };

        self.buffer.clear();
        if self.answered.contains(&prompt) {
            return None;
        }
        self.answered.push(prompt);
        Some(prompt)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn answers_each_prompt_once() {
        let mut d = PromptDetector::default();
        assert_eq!(d.consume("Enter password for Teleport user bob:"), Some(Prompt::Password));
        assert_eq!(d.consume("Enter password for Teleport user bob:"), None);
        assert_eq!(d.consume("Enter an OTP code from a device:"), Some(Prompt::OneTimePassword));
    }

    #[test]
    fn parses_item_fields() {
        let json = r#"{"fields":[{"purpose":"USERNAME","value":"bob"},{"label":"Password","value":"s3cret"}]}"#;
        let c = parse_credentials(json).unwrap();
        assert_eq!((c.username.as_deref(), c.password.as_str()), (Some("bob"), "s3cret"));
        assert!(parse_credentials(r#"{"fields":[]}"#).is_err());
    }
}
