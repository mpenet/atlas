# TLS and proxies

[Documentation](README.md) › TLS and proxies

Server certificates are verified, both the chain and the host name, against the system's CA certificates: the file named by `SSL_CERT_FILE` when set, else the usual bundle of macOS and of the major Linux distributions, else the directory named by `SSL_CERT_DIR`. Without any of them, HTTPS requests fail rather than go unverified.

A profile's `tls` sets a client certificate for mutual TLS (also used to fetch the spec), or a CA bundle to trust instead of the system's:

```json
"tls": {"cert": "/path/to/client.pem", "key": "/path/to/client.key", "ca_cert": "/path/to/ca.pem"}
```

`"insecure": true`, or `--ssl.verify=none` for one command, turns verification off. Don't use it outside of testing.

`ssl` takes the same settings under other names (`certificate`, `key`, `cafile`), plus `capath`, a directory of CA certificates; `tls` wins when both set the same thing.

Requests go through the proxy named by `https_proxy` or `HTTPS_PROXY` (HTTPS requests), `http_proxy` (HTTP requests; libcurl ignores the upper-case form, which CGI environments can set from a request header) or `all_proxy`/`ALL_PROXY`, except for the hosts listed in `no_proxy`/`NO_PROXY`. The proxy URL can carry credentials (`http://user:secret@proxy:3128`).
