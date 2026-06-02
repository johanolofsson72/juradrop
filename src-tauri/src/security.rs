// Spec 030 — strict Content-Security-Policy.
//
// This module does not run at runtime: Tauri enforces the CSP declared in
// `tauri.conf.json` inside the WKWebView. What lives here is the parser +
// the pinning test that locks the production policy to Constitution
// Principle I (no document content ever leaves the Mac). The test reads the
// REAL bundled `tauri.conf.json` so a future edit that loosens the policy —
// adds a remote `connect-src`, an `'unsafe-inline'` script source, or a
// violation-reporting endpoint — fails CI instead of silently shipping.

/// A parsed CSP directive: its name and the list of source tokens.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Directive {
    pub name: String,
    pub sources: Vec<String>,
}

/// Parse a Content-Security-Policy string into its directives. Directives are
/// `;`-separated; within a directive the first whitespace token is the name
/// and the rest are sources. Empty segments are ignored.
pub fn parse_csp(policy: &str) -> Vec<Directive> {
    policy
        .split(';')
        .filter_map(|segment| {
            let mut tokens = segment.split_whitespace();
            let name = tokens.next()?.to_string();
            Some(Directive {
                name,
                sources: tokens.map(str::to_string).collect(),
            })
        })
        .collect()
}

/// The sources of a named directive, or an empty slice-owned vec if absent.
pub fn directive_sources<'a>(directives: &'a [Directive], name: &str) -> Vec<&'a str> {
    directives
        .iter()
        .find(|d| d.name == name)
        .map(|d| d.sources.iter().map(String::as_str).collect())
        .unwrap_or_default()
}

/// True if a CSP source token names a remote network host (an `http(s)://`
/// origin that is NOT a localhost form). `'self'`, `ipc:`, `data:`,
/// `'unsafe-inline'`, `'none'` and the localhost/127.0.0.1 origins are local.
pub fn is_remote_host(source: &str) -> bool {
    let lower = source.to_ascii_lowercase();
    let host = if let Some(rest) = lower.strip_prefix("http://") {
        rest
    } else if let Some(rest) = lower.strip_prefix("https://") {
        rest
    } else if let Some(rest) = lower.strip_prefix("ws://") {
        rest
    } else if let Some(rest) = lower.strip_prefix("wss://") {
        rest
    } else {
        return false; // keyword source ('self', data:, ipc:, 'none', ...)
    };
    let host = host.split('/').next().unwrap_or(host);
    !(host.starts_with("127.0.0.1")
        || host.starts_with("localhost")
        || host.starts_with("ipc.localhost")
        || host.starts_with("asset.localhost")
        || host.starts_with("tauri.localhost"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    /// The bundled production config, read at compile time so the test pins
    /// the policy that actually ships.
    const TAURI_CONF: &str = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/tauri.conf.json"));

    fn security() -> Value {
        let conf: Value = serde_json::from_str(TAURI_CONF).expect("tauri.conf.json parses");
        conf["app"]["security"].clone()
    }

    fn prod_csp() -> String {
        security()["csp"]
            .as_str()
            .expect("app.security.csp is a string (C-1 / FR-001)")
            .to_string()
    }

    fn dev_csp() -> String {
        security()["devCsp"]
            .as_str()
            .expect("app.security.devCsp is a string (FR-015)")
            .to_string()
    }

    // The five origins the renderer may ever connect to (FR-002/003).
    const ALLOWED_CONNECT: [&str; 5] = [
        "'self'",
        "ipc:",
        "http://ipc.localhost",
        "http://127.0.0.1:11434",
        "http://localhost:11434",
    ];

    // ---- C-1 / FR-001: the policy is declared, not null ----
    #[test]
    fn c1_csp_is_declared_non_empty() {
        let csp = prod_csp();
        assert!(!csp.trim().is_empty(), "production csp must not be empty");
        // (csp being null/absent would already have panicked in prod_csp())
    }

    // ---- C-2 / FR-002,003 / SC-005: connect-src is localhost-only ----
    #[test]
    fn c2_connect_src_is_localhost_only() {
        let dirs = parse_csp(&prod_csp());
        let connect = directive_sources(&dirs, "connect-src");
        assert!(!connect.is_empty(), "connect-src must be present");
        for src in &connect {
            assert!(
                ALLOWED_CONNECT.contains(src),
                "connect-src carries a non-allowed origin: {src} (LocalhostOnlyEgress)"
            );
            assert!(
                !is_remote_host(src),
                "connect-src carries a remote host: {src} (SC-005 — egress origins must be 0)"
            );
        }
    }

    // ---- C-3 / FR-004,012: script-src is self only, no unsafe ----
    #[test]
    fn c3_script_src_self_only_no_unsafe() {
        let dirs = parse_csp(&prod_csp());
        let script = directive_sources(&dirs, "script-src");
        assert_eq!(
            script,
            vec!["'self'"],
            "script-src must be exactly 'self' (Tauri injects hashes at build); \
             no remote host, no 'unsafe-inline'/'unsafe-eval'"
        );
    }

    // ---- C-4 / FR-013: no violation-reporting endpoint ----
    #[test]
    fn c4_no_report_endpoint() {
        let csp = prod_csp().to_ascii_lowercase();
        assert!(
            !csp.contains("report-uri") && !csp.contains("report-to"),
            "a report endpoint is outbound traffic — forbidden by Principle I (FR-013)"
        );
    }

    // ---- C-5 / FR-014: defense-in-depth directives present + locked ----
    #[test]
    fn c5_defense_in_depth_locked() {
        let dirs = parse_csp(&prod_csp());
        assert_eq!(directive_sources(&dirs, "object-src"), vec!["'none'"]);
        assert_eq!(directive_sources(&dirs, "base-uri"), vec!["'self'"]);
        assert_eq!(directive_sources(&dirs, "frame-ancestors"), vec!["'none'"]);
        assert_eq!(directive_sources(&dirs, "form-action"), vec!["'self'"]);
    }

    // ---- C-6 / FR-005: resource directives carry no remote host ----
    #[test]
    fn c6_resource_directives_local_only() {
        let dirs = parse_csp(&prod_csp());
        for name in ["default-src", "style-src", "img-src", "font-src"] {
            for src in directive_sources(&dirs, name) {
                assert!(
                    !is_remote_host(src),
                    "{name} carries a remote host: {src} (ResourcesAreLocalOnly)"
                );
            }
        }
    }

    // ---- C-7 / FR-015: devCsp is dev-only relaxation, never relaxes guards ----
    #[test]
    fn c7_devcsp_relaxes_only_dev_origin_and_keeps_guards() {
        let dev = dev_csp();
        let dirs = parse_csp(&dev);
        // dev still forbids report endpoints and keeps defense-in-depth locked
        let lower = dev.to_ascii_lowercase();
        assert!(
            !lower.contains("report-uri") && !lower.contains("report-to"),
            "devCsp must not add a report endpoint (FR-015)"
        );
        assert_eq!(directive_sources(&dirs, "object-src"), vec!["'none'"]);
        assert_eq!(directive_sources(&dirs, "base-uri"), vec!["'self'"]);
        assert_eq!(directive_sources(&dirs, "frame-ancestors"), vec!["'none'"]);
        assert_eq!(directive_sources(&dirs, "form-action"), vec!["'self'"]);
        // every remote host dev adds must be the localhost Vite dev server only
        for name in ["default-src", "script-src", "style-src", "connect-src"] {
            for src in directive_sources(&dirs, name) {
                assert!(
                    !is_remote_host(src),
                    "devCsp {name} carries a non-localhost host: {src} (FR-015)"
                );
            }
        }
        // connect-src in dev must additionally allow the HMR websocket
        assert!(
            directive_sources(&dirs, "connect-src").contains(&"ws://localhost:1420"),
            "devCsp connect-src must allow the Vite HMR websocket"
        );
    }

    // ---- T010-T012: the pin must be able to FAIL (else it rubber-stamps) ----

    #[test]
    fn t010_detects_smuggled_remote_connect_host() {
        let bad = "default-src 'self'; connect-src 'self' https://evil.example.com";
        let dirs = parse_csp(bad);
        let leaked = directive_sources(&dirs, "connect-src")
            .iter()
            .any(|s| is_remote_host(s) || !ALLOWED_CONNECT.contains(s));
        assert!(
            leaked,
            "parser must catch a smuggled remote connect-src host"
        );
    }

    #[test]
    fn t011_detects_unsafe_inline_script() {
        let bad = "script-src 'self' 'unsafe-inline'";
        let dirs = parse_csp(bad);
        assert_ne!(
            directive_sources(&dirs, "script-src"),
            vec!["'self'"],
            "parser must catch 'unsafe-inline' added to script-src"
        );
    }

    #[test]
    fn t012_detects_report_endpoint() {
        let bad = "default-src 'self'; report-to https://collector.example.com";
        assert!(
            bad.to_ascii_lowercase().contains("report-to"),
            "report endpoint detection must trip on a report-to token"
        );
    }

    // is_remote_host unit coverage
    #[test]
    fn is_remote_host_classifies_correctly() {
        assert!(is_remote_host("https://evil.example.com"));
        assert!(is_remote_host("http://cdn.jsdelivr.net"));
        assert!(is_remote_host("wss://remote.example.com"));
        assert!(!is_remote_host("'self'"));
        assert!(!is_remote_host("data:"));
        assert!(!is_remote_host("ipc:"));
        assert!(!is_remote_host("'none'"));
        assert!(!is_remote_host("http://127.0.0.1:11434"));
        assert!(!is_remote_host("http://localhost:11434"));
        assert!(!is_remote_host("http://ipc.localhost"));
        assert!(!is_remote_host("ws://localhost:1420"));
    }
}
