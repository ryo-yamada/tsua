# Changelogs
This is a changelog tracker for the `tsua.lua` file, not for the entire repository.

### v1.3
- Implemented DELETE method
- Added 2 helper funcs:
    - `res:redirect()`, allows redirecting clients to other pages easily
    - `res:json()`, allows for in-framework json encoding and sending. Encode function must be user-provided since any other approach would complicate tsua
- More MIME types
- Slightly refactored and improved the error system

### v1.2.1
- Implemented PUT method
- Made a helper function that escapes HTML, good for security (`res:escape()`)

### v1.2
- Implemented dynamic routing

### v1.1.3
- Implemented URL query parsing support

### v1.1.2
- Fixed `404` and `403` logs showing up as `???` in the terminal
- Small reforms/refactors

### v1.1.1
- Enhancement of default error pages, thanks to @saurabhhhcodes for the PR

### v1.1
- Implemented async, a single client no longer blocks everything

### v1.0.1.1
- Allowed for more configuration
- Improved logging

### v1.0.1
- Implemented POST
- Implemented some error handling
- Small code refactors

### v1.0
- Initial release