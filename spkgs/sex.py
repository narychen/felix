caml_modules = [
  'src/compiler/sex/sex_types',
  'src/compiler/sex/sex_token',
  'src/compiler/sex/sex_parse',
  'src/compiler/sex/sex_lex',
  'src/compiler/sex/sex_print',
  'src/compiler/sex/sex_map',
  'src/compiler/sex/ocs2sex',
  ]

caml_include_paths = ['src/compiler/ocs','src/compiler/dyp/dyplib','src/compiler/sex']
caml_provide_lib = 'src/compiler/sex/sexlib'
caml_require_libs = ['dyplib','ocslib','sexlib']
pkg_requires = ['ocs','dypgen']
caml_exes = ['src/compiler/sex/sex']
weaver_directory='doc/sex'
tmpdir = ['sex']