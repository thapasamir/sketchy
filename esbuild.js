const esbuild = require('esbuild')
const sveltePlugin = require('esbuild-svelte')

const watch = process.argv.includes('--watch')
const prod = process.env.NODE_ENV === 'production' || process.env.MIX_ENV === 'prod'

const options = {
  entryPoints: ['assets/js/app.js'],
  bundle: true,
  target: 'es2022',
  outdir: 'priv/static/assets',
  sourcemap: !prod,
  minify: prod,
  logLevel: 'info',
  plugins: [sveltePlugin({ compilerOptions: { css: 'injected' } })],
}

if (watch) {
  esbuild.context(options).then(ctx => {
    ctx.watch()
    // Phoenix closes stdin when the server stops; exit with it so no orphan watcher is left
    process.stdin.on('close', () => { ctx.dispose(); process.exit(0) })
    process.stdin.resume()
  })
} else {
  esbuild.build(options).catch(() => process.exit(1))
}
