# Permissions

## Roles

| Role | Source |
|---|---|
| Unauthenticated network caller | No valid bearer token |
| Paired Android client | Token stored in an Android private profile |
| Local desktop user | OS account owning the token and startup service |
| Release maintainer | Local signing key/Keychain or protected GitHub repository secrets |

## Access Matrix

| Resource / operation | Unauthenticated | Paired client | Local user |
|---|---:|---:|---:|
| `GET /health` | Allow: availability only | Allow | Allow |
| `GET /status` | Deny `401` | Allow | Allow with token |
| `POST /send` | Deny `401` | Allow after all request validation | Allow with token |
| Web console | Deny `401` | Not normally used | Allow with header or bootstrap query token |
| Read/replace token | Deny by OS permissions | No desktop filesystem access | Allow |
| Install startup service | Deny | Deny | Allow in current user scope |
| Sign Android release | Deny | Deny | Maintainer credentials only |

There is no database or row-level security. Authorization is token-based and enforced in `common/bridge_server.py` on every protected HTTP path.
