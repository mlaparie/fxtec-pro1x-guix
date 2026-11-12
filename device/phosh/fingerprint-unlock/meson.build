name = 'fingerprint-unlock'

shared_module(
  'phosh-plugin-fingerprint-unlock',
  files('phosh-plugin-fingerprint-unlock.c'),
  c_args: [
    '-DG_LOG_DOMAIN="phosh-plugin-@0@"'.format(name),
    '-DPLUGIN_NAME="@0@"'.format(name),
  ],
  dependencies: [plugin_dep],
  install: true,
  install_dir: plugins_dir,
)

pluginconf = configuration_data()
pluginconf.set('name', name)
pluginconf.set('plugins_dir', plugins_dir)

configure_file(
  input: name + '.plugin.in',
  output: name + '.plugin',
  configuration: pluginconf,
  install: true,
  install_dir: plugins_dir,
)
