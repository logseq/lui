//! Optional loopback transport for the shared OCaml lui-agent protocol.
use std::{
    io::{BufRead, BufReader, Read, Write},
    net::{Shutdown, SocketAddr, TcpListener, TcpStream},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

const MAX_LINE: u64 = 1024 * 1024;

pub(crate) struct Server {
    address: SocketAddr,
    stopped: Arc<AtomicBool>,
    active: Arc<Mutex<Option<TcpStream>>>,
}

impl Server {
    pub(crate) fn start(
        address: &str,
        answer: impl Fn(String) -> Result<String, String> + Send + 'static,
    ) -> Result<Self, String> {
        let address: SocketAddr = address
            .parse()
            .map_err(|e| format!("lui-agent address: {e}"))?;
        if !address.ip().is_loopback() {
            return Err("lui-agent requires a numeric loopback address".into());
        }
        let listener = TcpListener::bind(address).map_err(|e| format!("lui-agent bind: {e}"))?;
        let address = listener.local_addr().map_err(|e| e.to_string())?;
        let stopped = Arc::new(AtomicBool::new(false));
        let active: Arc<Mutex<Option<TcpStream>>> = Arc::default();
        let worker_stopped = stopped.clone();
        let worker_active = active.clone();
        std::thread::Builder::new()
            .name("lui-agent".into())
            .spawn(move || {
                for connection in listener.incoming() {
                    let Ok(mut stream) = connection else { break };
                    let Ok(mut current) = worker_active.lock() else {
                        break;
                    };
                    *current = stream.try_clone().ok();
                    drop(current);
                    // Check after publishing the active stream: teardown can
                    // interrupt a reader even if it raced the preceding accept.
                    if worker_stopped.load(Ordering::Acquire) {
                        break;
                    }
                    let Ok(reader) = stream.try_clone() else {
                        continue;
                    };
                    let mut reader = BufReader::new(reader);
                    loop {
                        let mut line = Vec::new();
                        let read = Read::by_ref(&mut reader)
                            .take(MAX_LINE + 2)
                            .read_until(b'\n', &mut line);
                        if !matches!(read, Ok(length) if length > 0)
                            || worker_stopped.load(Ordering::Acquire)
                        {
                            break;
                        }
                        if line.last() == Some(&b'\n') {
                            line.pop();
                        }
                        if line.last() == Some(&b'\r') {
                            line.pop();
                        }
                        let oversized = line.len() as u64 > MAX_LINE;
                        let reply = if oversized {
                            Err("lui-agent request exceeds 1 MiB".into())
                        } else {
                            String::from_utf8(line)
                                .map_err(|_| "lui-agent request is not UTF-8".into())
                                .and_then(&answer)
                        };
                        let reply = reply.unwrap_or_else(|error: String| {
                            serde_json::json!({"ok": false, "error": error}).to_string()
                        });
                        if stream.write_all(reply.as_bytes()).is_err()
                            || stream.write_all(b"\n").is_err()
                            || oversized
                        {
                            break;
                        }
                    }
                    if let Ok(mut current) = worker_active.lock() {
                        current.take();
                    }
                    if worker_stopped.load(Ordering::Acquire) {
                        break;
                    }
                }
            })
            .map_err(|e| format!("lui-agent worker: {e}"))?;
        eprintln!("lui-agent listening on {address}");
        Ok(Self {
            address,
            stopped,
            active,
        })
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::Release);
        if let Ok(active) = self.active.lock()
            && let Some(stream) = active.as_ref()
        {
            let _ = stream.shutdown(Shutdown::Both);
        }
        // Wake a blocking accept without a polling loop or a UI-thread join.
        let _ = TcpStream::connect_timeout(&self.address, std::time::Duration::from_millis(50));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn connect(server: &Server) -> TcpStream {
        let stream = TcpStream::connect(server.address).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        stream
    }

    #[test]
    fn loopback_lines_preserve_utf8_and_report_handler_errors() {
        let server = Server::start("127.0.0.1:0", |line| {
            if line == "fail" {
                Err("refused".into())
            } else {
                Ok(serde_json::json!({"ok": true, "text": line}).to_string())
            }
        })
        .unwrap();
        let mut stream = connect(&server);
        stream.write_all("你好\r\nfail\n".as_bytes()).unwrap();
        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let first: serde_json::Value = serde_json::from_str(&line).unwrap();
        assert_eq!(first["text"], "你好");
        line.clear();
        reader.read_line(&mut line).unwrap();
        let second: serde_json::Value = serde_json::from_str(&line).unwrap();
        assert_eq!(second["ok"], false);
        assert_eq!(second["error"], "refused");
        drop(server);
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => {}
            Err(error)
                if matches!(
                    error.kind(),
                    std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionAborted
                ) => {}
            result => panic!("agent teardown did not close its active connection: {result:?}"),
        }
    }

    #[test]
    fn oversized_requests_are_rejected_before_dispatch() {
        let server =
            Server::start("127.0.0.1:0", |_| panic!("oversized request dispatched")).unwrap();
        let mut stream = connect(&server);
        stream
            .write_all(&vec![b'x'; MAX_LINE as usize + 2])
            .unwrap();
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).unwrap();
        let response: serde_json::Value = serde_json::from_str(&line).unwrap();
        assert_eq!(response["ok"], false);
        assert!(response["error"].as_str().unwrap().contains("1 MiB"));
    }

    #[test]
    fn public_network_addresses_are_refused() {
        assert!(Server::start("0.0.0.0:0", Ok).is_err());
    }
}
