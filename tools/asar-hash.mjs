import * as asar from '@electron/asar'; import c from 'crypto';
const f=process.argv[2];
console.log(c.createHash('sha256').update(asar.getRawHeader(f).headerString).digest('hex'));
