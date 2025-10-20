// debug-auth.js
const auth = require('./middleware/auth');
console.log('middleware/auth exports =>', Object.keys(auth), 'requireRole type:', typeof auth.requireRole);
