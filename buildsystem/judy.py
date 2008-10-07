import fbuild
from fbuild.path import Path
from fbuild.record import Record

import buildsystem

# -----------------------------------------------------------------------------

def build_runtime(phase):
    path = Path('src/judy')

    buildsystem.copy_hpps_to_rtl(path / 'Judy.h')

    dst = fbuild.buildroot / 'lib/rtl/flx_judy'
    srcs = [
        path / 'JudyCommon/JudyMalloc.c',
        path / 'Judy1/JUDY1_Judy1ByCount.c',
        path / 'Judy1/JUDY1_Judy1Cascade.c',
        path / 'Judy1/JUDY1_Judy1Count.c',
        path / 'Judy1/JUDY1_Judy1CreateBranch.c',
        path / 'Judy1/JUDY1_Judy1Decascade.c',
        path / 'Judy1/JUDY1_Judy1First.c',
        path / 'Judy1/JUDY1_Judy1FreeArray.c',
        path / 'Judy1/JUDY1_Judy1InsertBranch.c',
        path / 'Judy1/JUDY1_Judy1MallocIF.c',
        path / 'Judy1/JUDY1_Judy1MemActive.c',
        path / 'Judy1/JUDY1_Judy1MemUsed.c',
        path / 'Judy1/JUDY1_Judy1SetArray.c',
        path / 'Judy1/JUDY1_Judy1Set.c',
        path / 'Judy1/JUDY1_Judy1Tables.c',
        path / 'Judy1/JUDY1_Judy1Unset.c',
        path / 'Judy1/JUDY1_Judy1Next.c',
        path / 'Judy1/JUDY1_Judy1NextEmpty.c',
        path / 'Judy1/JUDY1_Judy1Prev.c',
        path / 'Judy1/JUDY1_Judy1PrevEmpty.c',
        path / 'Judy1/JUDY1_Judy1Test.c',
        path / 'Judy1/JUDY1_j__udy1Test.c',
        path / 'JudyL/JUDYL_JudyLByCount.c',
        path / 'JudyL/JUDYL_JudyLCascade.c',
        path / 'JudyL/JUDYL_JudyLCount.c',
        path / 'JudyL/JUDYL_JudyLCreateBranch.c',
        path / 'JudyL/JUDYL_JudyLDecascade.c',
        path / 'JudyL/JUDYL_JudyLDel.c',
        path / 'JudyL/JUDYL_JudyLFirst.c',
        path / 'JudyL/JUDYL_JudyLFreeArray.c',
        path / 'JudyL/JUDYL_JudyLInsArray.c',
        path / 'JudyL/JUDYL_JudyLIns.c',
        path / 'JudyL/JUDYL_JudyLInsertBranch.c',
        path / 'JudyL/JUDYL_JudyLMemActive.c',
        path / 'JudyL/JUDYL_JudyLMemUsed.c',
        path / 'JudyL/JUDYL_JudyLMallocIF.c',
        path / 'JudyL/JUDYL_JudyLTables.c',
        path / 'JudyL/JUDYL_JudyLNext.c',
        path / 'JudyL/JUDYL_JudyLNextEmpty.c',
        path / 'JudyL/JUDYL_JudyLPrev.c',
        path / 'JudyL/JUDYL_JudyLPrevEmpty.c',
        path / 'JudyL/JUDYL_JudyLGet.c',
        path / 'JudyL/JUDYL_j__udyLGet.c',
        path / 'JudyHS/JudyHS.c',
    ]

    includes = [
        path,
        path / 'JudyCommon',
        path / 'Judy1',
        path / 'JudyL',
        path / 'JudyHS',
    ]

    types = fbuild.env.cache('fbuild.builders.c.std.config_types',
        phase.c.shared)

    macros = ['BUILD_JUDY']
    if types['void*']['size'] == 8:
        macros.append('JU_64BIT')
    else:
        macros.append('JU_32BIT')

    return Record(
        static=phase.c.static.build_lib(dst + '_static', srcs,
            includes=includes,
            macros=macros + ['FLX_STATIC_LINK']),
        shared=phase.c.shared.build_lib(dst + '_dynamic', srcs,
            includes=includes,
            macros=macros))

def build_flx(builder):
    return buildsystem.copy_flxs_to_lib(Path('src/judy/*.flx').glob())