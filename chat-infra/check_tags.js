const https = require('https');
https.get('https://api.github.com/repos/sebadob/rauthy/releases?per_page=100', { headers: { 'User-Agent': 'Node.js' } }, res => {
  let d = '';
  res.on('data', c => d += c);
  res.on('end', () => {
    try {
      console.log(JSON.parse(d).map(x => x.tag_name));
    } catch(e) { console.log(e); }
  });
});
