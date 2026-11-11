// Loads the classic-script libraries in the order the extension does and
// returns their shared namespace.
import '../src/lib/url.js';
import '../src/lib/crypto.js';
import '../src/lib/client.js';
import '../src/lib/router.js';
import '../src/lib/forms.js';

export default globalThis.Arcanum;
