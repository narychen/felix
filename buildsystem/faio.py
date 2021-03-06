import fbuild
from fbuild.functools import call
from fbuild.path import Path
from fbuild.record import Record

import buildsystem

# ------------------------------------------------------------------------------

def build_runtime(phase):
    path = Path('src/faio')

    buildsystem.copy_hpps_to_rtl(phase.ctx,
        phase.ctx.buildroot / 'config/target/flx_faio_config.hpp',
        path / 'faio_job.hpp',
        path / 'faio_timer.hpp',
        path / 'faio_posixio.hpp',
        path / 'faio_winio.hpp',
    )

    dst = 'lib/rtl/faio'
    srcs = [
        path / 'faio_job.cpp',
        path / 'faio_timer.cpp',
    ]
    includes = [
        phase.ctx.buildroot / 'config/target',
        Path('src', 'flx_async'),
        Path('src', 'pthread'),
        Path('src', 'demux'),
        Path('src', 'rtl'),
        Path('src', 'exceptions'),
        Path('src', 'gc'),
        path,
    ]
    macros = ['BUILD_FAIO']
    libs=[
        call('buildsystem.flx_pthread.build_runtime', phase),
        call('buildsystem.flx_async.build_runtime', phase),
        call('buildsystem.demux.build_runtime', phase),
    ]

    if 'win32' in phase.platform:
        srcs.append(path / 'faio_winio.cpp')
        includes.append(Path('src', 'demux', 'win'))

    if 'posix' in phase.platform:
        srcs.append(path / 'faio_posixio.cpp')
        includes.append(Path('src', 'demux', 'posix'))

    return Record(
        static=buildsystem.build_cxx_static_lib(phase, dst, srcs,
            includes=includes,
            macros=macros,
            libs=[lib.static for lib in libs]),
        shared=buildsystem.build_cxx_shared_lib(phase, dst, srcs,
            includes=includes,
            macros=macros,
            libs=[lib.shared for lib in libs]))

def build_flx(phase):
    return buildsystem.copy_flxs_to_lib(phase.ctx,
        Path('src/faio/*.flx').glob())
