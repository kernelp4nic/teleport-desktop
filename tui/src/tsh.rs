use std::{collections::BTreeMap, process::Command};

use serde_json::Value;

pub struct Node {
    pub hostname: String,
    pub labels: BTreeMap<String, String>,
    pub haystack: String,
}

#[derive(Default)]
pub struct Session {
    pub summary: String,
    pub logins: Vec<String>,
}

fn tsh_json(args: &[&str]) -> Result<Value, String> {
    let out = Command::new("tsh").args(args).output().map_err(|e| format!("tsh: {e}"))?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }
    serde_json::from_slice(&out.stdout).map_err(|e| e.to_string())
}

pub fn load_session() -> Result<Session, String> {
    let status = tsh_json(&["status", "--format=json"])?;
    let active = status.get("active").ok_or("no active session, run `tsh login`")?;
    let text = |k: &str| active[k].as_str().unwrap_or("?");
    let logins = active["logins"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|v| v.as_str())
        .filter(|l| !l.starts_with("-teleport-"))
        .map(String::from)
        .collect();
    Ok(Session { summary: format!("{}@{}", text("username"), text("cluster")), logins })
}

pub fn load_nodes(proxy: Option<&str>) -> Result<Vec<Node>, String> {
    let proxy_arg = proxy.map(|p| format!("--proxy={p}"));
    let mut args = vec!["ls", "--format=json"];
    args.extend(proxy_arg.as_deref());
    let raw = tsh_json(&args)?;

    let mut nodes: Vec<Node> = raw
        .as_array()
        .into_iter()
        .flatten()
        .map(|n| {
            let name = n["metadata"]["name"].as_str().unwrap_or("unknown");
            let hostname = n["spec"]["hostname"].as_str().unwrap_or(name).to_string();
            let mut labels = BTreeMap::new();
            for (k, v) in n["metadata"]["labels"].as_object().into_iter().flatten() {
                labels.insert(k.clone(), v.as_str().unwrap_or_default().to_string());
            }
            // Dynamic labels override static ones, as in the desktop app.
            for (k, v) in n["spec"]["cmd_labels"].as_object().into_iter().flatten() {
                let result = v.as_str().or_else(|| v["result"].as_str()).unwrap_or_default();
                if !result.is_empty() {
                    labels.insert(k.clone(), result.to_string());
                }
            }
            let haystack = std::iter::once(hostname.clone())
                .chain(labels.iter().map(|(k, v)| format!("{k} {v}")))
                .collect::<Vec<_>>()
                .join(" ");
            Node { hostname, labels, haystack }
        })
        .collect();
    nodes.sort_by_key(|n| n.hostname.to_lowercase());
    Ok(nodes)
}
