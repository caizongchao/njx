---@diagnostic disable: local-limit
local ninja = _G['ninja']
local fs = _G['fs']
local path = _G['path']
local public = _G['public']
local files_in = _G['files_in']
local options_tostring = _G['options_tostring']
local as_list = _G['as_list']
local inspect = _G['inspect']

ninja.ccache = 'sccache'

local LLVM_ROOT = 'llvm/'
local LLVM_DIR = 'llvm/llvm/'
local LLVM_LIB_DIR = LLVM_DIR .. 'lib/'
local LLVM_INCLUDE_DIR = LLVM_DIR .. 'include/'

local OPT = '/O2'

local llvm = ninja.target('llvm')
    :type('phony')
    :define(public { '_WIN32' })
    :cx_flags(public { OPT, '/EHsc', '/wd4244', '/wd4319', '/wd4291', '/wd4819', '/wd4267', '/wd4805', '/wd4624' })
    :cxx_flags(public { std = 'c++17' })
    :include_dir(public {
        './include',
        LLVM_INCLUDE_DIR
    })

local LLVM_LIBSUPPORT_DIR = LLVM_LIB_DIR .. 'Support/'

local libsupport = ninja.target('libsupport')
    :type('static')
    :deps(llvm)
    :src(LLVM_LIBSUPPORT_DIR .. '*.cpp')
    :src(LLVM_LIBSUPPORT_DIR .. '*.c')
    :src(files_in { LLVM_LIBSUPPORT_DIR .. 'BLAKE3/',
        'blake3.c',
        'blake3_dispatch.c',
        'blake3_portable.c',
        'blake3_sse2.c',
        'blake3_sse41.c',
        'blake3_avx2.c',
        'blake3_avx512.c',
    })

local LLVM_LIBTABLEGEN_DIR = LLVM_LIB_DIR .. '/TableGen/'
local LLVM_TABLEGEN_DIR = LLVM_DIR .. 'utils/TableGen/'

local skip_build_tablegen

local tablegen_cmd; do
    local s = path.combine(ninja.build_dir(), 'tablegen.exe')

    if fs.file_exists(s) then
        tablegen_cmd = s; skip_build_tablegen = true
    end
end

local libtablegen = ninja.target('libtablegen')
    :type('static')
    :deps(llvm)
    :src(LLVM_LIBTABLEGEN_DIR .. '*.cpp')

local tablegen_min = ninja.target('tablegen_min')
    :type('binary')
    :deps(libsupport, libtablegen)
    :src(files_in { LLVM_TABLEGEN_DIR,
        'Attributes.cpp',
        'CodeGenIntrinsics.cpp',
        'DirectiveEmitter.cpp',
        'IntrinsicEmitter.cpp',
        'RISCVTargetDefEmitter.cpp',
        'SDNodeProperties.cpp',
        'VTEmitter.cpp',
    })
    :src(LLVM_TABLEGEN_DIR .. 'TableGen.cpp')

if not skip_build_tablegen then
    ninja.build(tablegen_min); tablegen_cmd = tablegen_min.output
end

local tablegen_tool = function(opts, infname)
    if infname ~= nil then
        if type(opts.output) == 'function' then
            return opts.output(infname)
        else
            return opts.output
        end
    else
        local include_dirs = ''; for _, dir in ipairs(as_list(opts.include_dir)) do
            include_dirs = include_dirs .. ' -I ' .. dir
        end

        local flags = ''; for _, flag in ipairs(as_list(opts.flags)) do
            flags = flag .. ' ' .. flag
        end

        return options_tostring(tablegen_cmd, opts.cmd, include_dirs, flags, '-o $out $in')
    end
end

local tablegen_valuetypes = ninja.target('tablegen_valuetypes')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            cmd = '-gen-vt',
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen' },
            flags = { '--write-if-changed' },
            output = function(infname)
                if path.fname(infname) == 'ValueTypes.td' then
                    return 'include/llvm/CodeGen/GenVT.inc'
                end
                assert(false, 'unknown tablegen input file: ' .. infname)
            end
        })
    :src(
        LLVM_INCLUDE_DIR .. 'llvm/CodeGen/ValueTypes.td'
    )

local tablegen = ninja.target('tablegen')
    :type('binary')
    :deps(libsupport, libtablegen, tablegen_valuetypes)
    :src(LLVM_TABLEGEN_DIR .. '*.cpp')
    :src(LLVM_TABLEGEN_DIR .. 'GlobalISel/*.cpp')

if not skip_build_tablegen then
    ninja.build(tablegen); tablegen_cmd = tablegen.output
end

-- set(LLVM_TARGET_DEFINITIONS ${PROJECT_SOURCE_DIR}/lib/Target/RISCV/RISCV.td)
-- tablegen(LLVM RISCVTargetParserDef.inc -gen-riscv-target-def -I ${PROJECT_SOURCE_DIR}/lib/Target/RISCV/)
-- add_public_tablegen_target(RISCVTargetParserTableGen)

local RISCV_TD = LLVM_LIB_DIR .. 'Target/RISCV/RISCV.td'
local RISCV_TD_OUTDIR = 'include/llvm/TargetParser/'

local tablegen_riscv = ninja.target('tablegen_riscv')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/RISCV' },
            flags = { '--write-if-changed' },
        })
    :src({
        RISCV_TD,
        cmd = '-gen-riscv-target-def',
        output = RISCV_TD_OUTDIR .. 'RISCVTargetParserDef.inc'
    })

local LLVM_TARGETPARSER_DIR = LLVM_DIR .. 'lib/TargetParser/'

local libtargetparser = ninja.target('libtargetparser')
    :type('static')
    :deps(libsupport, tablegen_riscv)
    :include_dir(RISCV_TD_OUTDIR)
    :src(LLVM_TARGETPARSER_DIR .. '*.cpp')

local LLVM_BINARYFORMAT_DIR = LLVM_DIR .. 'lib/BinaryFormat/'

local libbinaryformat = ninja.target('libbinaryformat')
    :type('static')
    :deps(libtargetparser)
    :src(LLVM_BINARYFORMAT_DIR .. '*.cpp')

local LLVM_BITSTREAM_DIR = LLVM_DIR .. 'lib/Bitstream/'

local libbitstream = ninja.target('libbitstream')
    :type('static')
    :deps(libsupport)
    :src(LLVM_BITSTREAM_DIR .. 'Reader/*.cpp')

local tablegen_attributes = ninja.target('tablegen_attributes')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            cmd = '-gen-attrs',
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen' },
            flags = { '--write-if-changed' },
            output = function(infname)
                return path.combine('include/llvm/IR', path.remove_extension(path.fname(infname)) .. '.inc')
            end
        })
    :src(
        LLVM_INCLUDE_DIR .. 'llvm/IR/Attributes.td'
    )

local INTRINSICS_TD = LLVM_INCLUDE_DIR .. 'llvm/IR/Intrinsics.td'
local INTRINSICS_TD_OUTDIR = 'include/llvm/IR/'

local tablegen_intrinsics = ninja.target('tablegen_intrinsics')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen' },
            flags = { '--write-if-changed' },
        })
    :src({
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-impl',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicImpl.inc'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicEnums.inc'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=arm',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsARM.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=x86',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsX86.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=nvvm',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsNVPTX.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=amdgcn',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsAMDGPU.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=bpf',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsBPF.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=dx',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsDirectX.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=hexagon',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsHexagon.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=loongarch',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsLoongArch.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=mips',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsMips.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=ppc',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsPowerPC.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=r600',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsR600.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=riscv',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsRISCV.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=spv',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsSPIRV.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=s390',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsS390.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=wasm',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsWebAssembly.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=xcore',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsXCore.h'
        },
        {
            INTRINSICS_TD,
            cmd = '-gen-intrinsic-enums -intrinsic-prefix=ve',
            output = INTRINSICS_TD_OUTDIR .. 'IntrinsicsVE.h'
        })

local LLVM_BITCODE_DIR = LLVM_DIR .. 'lib/Bitcode/'

local libbitcode = ninja.target('libbitcode')
    :type('static')
    :deps(libtargetparser, libbinaryformat, tablegen_attributes, tablegen_intrinsics)
    :src(LLVM_BITCODE_DIR .. 'Reader/*.cpp')
    :src(LLVM_BITCODE_DIR .. 'Writer/*.cpp')

local LLVM_DEMANGLE_DIR = LLVM_DIR .. 'lib/Demangle/'

local libdemangle = ninja.target('libdemangle')
    :type('static')
    :deps(libsupport)
    :src(LLVM_DEMANGLE_DIR .. '*.cpp')

local libremarks = ninja.target('libremarks')
    :type('static')
    :deps(libsupport, libbitstream)
    :src(LLVM_DIR .. 'lib/Remarks/*.cpp')

local LLVM_IR_DIR = LLVM_DIR .. 'lib/IR/'

local libir = ninja.target('libir')
    :type('static')
    :deps(libbinaryformat, libdemangle, libremarks, libtargetparser, tablegen_intrinsics)
    :src(LLVM_IR_DIR .. '*.cpp')
    :src(LLVM_LIB_DIR .. 'IRReader/*.cpp')
    :src(LLVM_LIB_DIR .. 'IRPrinter/*.cpp')

local libtextapi = ninja.target('libtextapi')
    :type('static')
    :deps(libsupport, libbinaryformat, libtargetparser)
    :src(LLVM_DIR .. 'lib/TextAPI/*.cpp')

local libdebuginfo_codeview = ninja.target('libdebuginfo_codeview')
    :type('static')
    :deps(libsupport)
    :src(LLVM_DIR .. 'lib/DebugInfo/CodeView/*.cpp')

local libdebuginfo_msf = ninja.target('libdebuginfo_msf')
    :type('static')
    :deps(libsupport)
    :src(LLVM_DIR .. 'lib/DebugInfo/MSF/*.cpp')

local libdebuginfo_pdb = ninja.target('libdebuginfo_pdb')
    :type('static')
    :deps(libdebuginfo_codeview, libdebuginfo_msf)
    :src(LLVM_DIR .. 'lib/DebugInfo/PDB/*.cpp')
    :src(LLVM_DIR .. 'lib/DebugInfo/PDB/Native/*.cpp')

local libdebuginfo_dwarf = ninja.target('libdebuginfo_dwarf')
    :type('static')
    :deps(libsupport)
    :src(LLVM_DIR .. 'lib/DebugInfo/DWARF/*.cpp')

local libdebuginfo_btf = ninja.target('libdebuginfo_btf')
    :type('static')
    :deps(libsupport)
    :src(LLVM_DIR .. 'lib/DebugInfo/BTF/*.cpp')

local libsymbolize = ninja.target('libsymbolize')
    :type('static')
    :deps(libdebuginfo_dwarf, libdebuginfo_btf, libdebuginfo_pdb)
    :src(LLVM_DIR .. 'lib/DebugInfo/Symbolize/*.cpp')

local libmc = ninja.target('libmc')
    :type('static')
    :deps(libtargetparser, libbinaryformat, libdebuginfo_codeview, tablegen_intrinsics)
    :src(LLVM_DIR .. 'lib/MC/*.cpp')
    :src(LLVM_DIR .. 'lib/MC/MCParser/*.cpp')
    :src(LLVM_DIR .. 'lib/MC/MCDisassembler/*.cpp')

local libmca = ninja.target('libmca')
    :type('static')
    :deps(libmc)
    :src(LLVM_DIR .. 'lib/MCA/*.cpp')

local libobject = ninja.target('libobject')
    :type('static')
    :deps(libbitcode, libmc, libtextapi)
    :src(LLVM_DIR .. 'lib/Object/*.cpp')

local libprofiledata = ninja.target('libprofiledata')
    :type('static')
    :deps(libobject, libdemangle, libsymbolize, tablegen_intrinsics)
    :src(LLVM_DIR .. 'lib/ProfileData/*.cpp')

local libanalysis = ninja.target('libanalysis')
    :type('static')
    :deps(libprofiledata, libtargetparser, libbinaryformat)
    :src(LLVM_DIR .. 'lib/Analysis/*.cpp')

local libasmparser = ninja.target('libasmparser')
    :type('static')
    :deps(libbinaryformat)
    :src(LLVM_DIR .. 'lib/AsmParser/*.cpp')

local OPENMP_TD = LLVM_INCLUDE_DIR .. 'llvm/Frontend/OpenMP/OMP.td'
local OPENMP_TD_OUTDIR = 'include/llvm/Frontend/OpenMP/'

local tablegen_omp = ninja.target('tablegen_omp')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen' },
            flags = { '--write-if-changed' },
        })
    :src({
            OPENMP_TD,
            cmd = '--gen-directive-decl',
            output = OPENMP_TD_OUTDIR .. 'OMP.h.inc'
        },
        {
            OPENMP_TD,
            cmd = '--gen-directive-impl',
            output = OPENMP_TD_OUTDIR .. 'OMP.inc'
        })

local libtransform_utils = ninja.target('libtransform_utils')
    :type('static')
    :deps(libanalysis, libtargetparser, tablegen_intrinsics)
    :src(LLVM_DIR .. 'lib/Transforms/Utils/*.cpp')

local libtransform_instcombine = ninja.target('libtransform_instcombine')
    :type('static')
    :deps(libtransform_utils)
    :src(LLVM_DIR .. 'lib/Transforms/InstCombine/*.cpp')

local libtransform_aggressiveinstcombine = ninja.target('libtransform_aggressiveinstcombine')
    :type('static')
    :deps(libtransform_utils)
    :src(LLVM_DIR .. 'lib/Transforms/AggressiveInstCombine/*.cpp')

local libtransform_objcarc = ninja.target('libtransform_objcarc')
    :type('static')
    :deps(libtransform_utils)
    :src(LLVM_DIR .. 'lib/Transforms/ObjCARC/*.cpp')

local libtransform_vectorize = ninja.target('libtransform_vectorize')
    :type('static')
    :deps(libtransform_utils)
    :src(LLVM_DIR .. 'lib/Transforms/Vectorize/*.cpp')

local libtransform_ipo = ninja.target('libtransform_ipo')
    :type('static')
    :deps(libtransform_vectorize, tablegen_omp)
    :src(LLVM_DIR .. 'lib/Transforms/IPO/*.cpp')

local libtransform_scalar = ninja.target('libtransform_scalar')
    :type('static')
    :deps(libtransform_instcombine, libtransform_aggressiveinstcombine)
    :src(LLVM_DIR .. 'lib/Transforms/Scalar/*.cpp')

local libtransform_cfguard = ninja.target('libtransform_cfguard')
    :type('static')
    :deps(libtransform_utils)
    :src(LLVM_DIR .. 'lib/Transforms/CFGuard/*.cpp')

local libtransform_coroutines = ninja.target('libtransform_coroutines')
    :type('static')
    :deps(libtransform_utils, libtransform_scalar, libtransform_ipo)
    :src(LLVM_DIR .. 'lib/Transforms/Coroutines/*.cpp')

local libtransform_instrummentation = ninja.target('libtransform_instrummentation')
    :type('static')
    :deps(libtransform_utils)
    :src(LLVM_DIR .. 'lib/Transforms/Instrumentation/*.cpp')

local libcodegen = ninja.target('libcodegen')
    :type('static')
    :deps(libanalysis, libmc, libtransform_objcarc, libprofiledata, libtransform_scalar, libtargetparser)
    :src(LLVM_DIR .. 'lib/CodeGen/*.cpp')
    :src(LLVM_DIR .. 'lib/CodeGen/AsmPrinter/*.cpp')
    :src(LLVM_DIR .. 'lib/CodeGen/GlobalISel/*.cpp')
    :src(LLVM_DIR .. 'lib/CodeGen/LiveDebugValues/*.cpp')
    :src(LLVM_DIR .. 'lib/CodeGen/MIRParser/*.cpp')
    :src(LLVM_DIR .. 'lib/CodeGen/SelectionDAG/*.cpp')

local libdwarf_linker = ninja.target('libdwarf_linker')
    :type('static')
    :deps(libcodegen, libdebuginfo_dwarf)
    :src(LLVM_DIR .. 'lib/DWARFLinker/*.cpp')
    :src(LLVM_DIR .. 'lib/DWARFLinkerParallel/*.cpp')

local libdwp = ninja.target('libdwp')
    :type('static')
    :deps(libdebuginfo_dwarf)
    :src(LLVM_DIR .. 'lib/DWP/*.cpp')

local X86_TD = LLVM_LIB_DIR .. 'target/X86/X86.td'
local X86_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_x86 = ninja.target('tablegen_x86')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/X86' },
            flags = { '--write-if-changed' },
        })
    :src(
        {
            X86_TD,
            cmd = '-gen-asm-matcher',
            output = X86_TD_OUTDIR .. 'X86GenAsmMatcher.inc'
        },
        {
            X86_TD,
            cmd = '-gen-asm-writer',
            output = X86_TD_OUTDIR .. 'X86GenAsmWriter.inc'
        },
        {
            X86_TD,
            cmd = '-gen-asm-writer -asmwriternum=1',
            output = X86_TD_OUTDIR .. 'X86GenAsmWriter1.inc'
        },
        {
            X86_TD,
            cmd = '-gen-callingconv',
            output = X86_TD_OUTDIR .. 'X86GenCallingConv.inc'
        },
        {
            X86_TD,
            cmd = '-gen-dag-isel',
            output = X86_TD_OUTDIR .. 'X86GenDAGISel.inc'
        },
        {
            X86_TD,
            cmd = '-gen-disassembler',
            output = X86_TD_OUTDIR .. 'X86GenDisassemblerTables.inc'
        },
        {
            X86_TD,
            cmd = '-gen-x86-EVEX2VEX-tables',
            output = X86_TD_OUTDIR .. 'X86GenEVEX2VEXTables.inc'
        },
        {
            X86_TD,
            cmd = '-gen-exegesis',
            output = X86_TD_OUTDIR .. 'X86GenExegesis.inc'
        },
        {
            X86_TD,
            cmd = '-gen-fast-isel',
            output = X86_TD_OUTDIR .. 'X86GenFastISel.inc'
        },
        {
            X86_TD,
            cmd = '-gen-global-isel',
            output = X86_TD_OUTDIR .. 'X86GenGlobalISel.inc'
        },
        {
            X86_TD,
            cmd = '-gen-instr-info -instr-info-expand-mi-operand-info=0',
            output = X86_TD_OUTDIR .. 'X86GenInstrInfo.inc'
        },
        {
            X86_TD,
            cmd = '-gen-x86-mnemonic-tables -asmwriternum=1',
            output = X86_TD_OUTDIR .. 'X86GenMnemonicTables.inc'
        },
        {
            X86_TD,
            cmd = '-gen-register-bank',
            output = X86_TD_OUTDIR .. 'X86GenRegisterBank.inc'
        },
        {
            X86_TD,
            cmd = '-gen-register-info',
            output = X86_TD_OUTDIR .. 'X86GenRegisterInfo.inc'
        },
        {
            X86_TD,
            cmd = '-gen-subtarget',
            output = X86_TD_OUTDIR .. 'X86GenSubtargetInfo.inc'
        },
        {
            X86_TD,
            cmd = '-gen-x86-fold-tables -asmwriternum=1',
            output = X86_TD_OUTDIR .. 'X86GenFoldTables.inc'
        }
    )

local libtarget_x86 = ninja.target('libtarget_x86')
    :type('static')
    :deps(llvm, tablegen_x86)
    :include_dir(LLVM_LIB_DIR .. 'Target/X86', X86_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/X86/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/X86/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/X86/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/X86/MCA/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/X86/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/X86/TargetInfo/*.cpp')

AARCH64_TD = LLVM_LIB_DIR .. 'Target/AArch64/AArch64.td'
AARCH64_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_aarch64 = ninja.target('tablegen_aarch64')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/AArch64' },
            flags = { '--write-if-changed' },
        })
    :src({
            AARCH64_TD,
            cmd = '-gen-asm-matcher',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenAsmMatcher.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-asm-writer',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenAsmWriter.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-asm-writer -asmwriternum=1',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenAsmWriter1.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-callingconv',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenCallingConv.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-dag-isel',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenDAGISel.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-disassembler',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenDisassemblerTables.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-exegesis',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenExegesis.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-fast-isel',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenFastISel.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-global-isel',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenGlobalISel.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-global-isel-combiner-matchtable -combiners=AArch64O0PreLegalizerCombiner',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenO0PreLegalizeGICombiner.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-global-isel-combiner-matchtable -combiners=AArch64PreLegalizerCombiner',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenPreLegalizeGICombiner.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-global-isel-combiner-matchtable -combiners=AArch64PostLegalizerCombiner',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenPostLegalizeGICombiner.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-global-isel-combiner-matchtable -combiners=AArch64PostLegalizerLowering',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenPostLegalizeGILowering.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-instr-info',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenInstrInfo.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-emitter',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenMCCodeEmitter.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-pseudo-lowering',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenMCPseudoLowering.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-register-bank',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenRegisterBank.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-register-info',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenRegisterInfo.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-subtarget',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenSubtargetInfo.inc'
        },
        {
            AARCH64_TD,
            cmd = '-gen-searchable-tables',
            output = AARCH64_TD_OUTDIR .. 'AArch64GenSystemOperands.inc'
        })

local libtarget_aarch64 = ninja.target('libtarget_aarch64')
    :type('static')
    :deps(llvm, tablegen_aarch64)
    :include_dir(AARCH64_TD_OUTDIR)
    :include_dir(LLVM_LIB_DIR .. 'Target/AArch64')
    :src(LLVM_LIB_DIR .. 'Target/AArch64/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AArch64/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AArch64/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AArch64/GISel/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AArch64/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AArch64/TargetInfo/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AArch64/Utils/*.cpp')

local ARM_TD = LLVM_LIB_DIR .. 'Target/ARM/ARM.td'
local ARM_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_arm = ninja.target('tablegen_arm')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/ARM' },
            flags = { '--write-if-changed' },
        })
    :src({
            ARM_TD,
            cmd = '-gen-asm-matcher',
            output = ARM_TD_OUTDIR .. 'ARMGenAsmMatcher.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-asm-writer',
            output = ARM_TD_OUTDIR .. 'ARMGenAsmWriter.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-callingconv',
            output = ARM_TD_OUTDIR .. 'ARMGenCallingConv.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-dag-isel',
            output = ARM_TD_OUTDIR .. 'ARMGenDAGISel.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-disassembler',
            output = ARM_TD_OUTDIR .. 'ARMGenDisassemblerTables.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-fast-isel',
            output = ARM_TD_OUTDIR .. 'ARMGenFastISel.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-global-isel',
            output = ARM_TD_OUTDIR .. 'ARMGenGlobalISel.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-instr-info',
            output = ARM_TD_OUTDIR .. 'ARMGenInstrInfo.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-emitter',
            output = ARM_TD_OUTDIR .. 'ARMGenMCCodeEmitter.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-pseudo-lowering',
            output = ARM_TD_OUTDIR .. 'ARMGenMCPseudoLowering.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-register-bank',
            output = ARM_TD_OUTDIR .. 'ARMGenRegisterBank.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-register-info',
            output = ARM_TD_OUTDIR .. 'ARMGenRegisterInfo.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-subtarget',
            output = ARM_TD_OUTDIR .. 'ARMGenSubtargetInfo.inc'
        },
        {
            ARM_TD,
            cmd = '-gen-searchable-tables',
            output = ARM_TD_OUTDIR .. 'ARMGenSystemRegister.inc'
        })

local libtarget_arm = ninja.target('libtarget_arm')
    :type('static')
    :deps(llvm, tablegen_arm)
    :include_dir(ARM_TD_OUTDIR)
    :include_dir(LLVM_LIB_DIR .. 'Target/ARM')
    :src(LLVM_LIB_DIR .. 'Target/ARM/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/ARM/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/ARM/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/ARM/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/ARM/TargetInfo/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/ARM/Utils/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS AMDGPU.td)

-- tablegen(LLVM AMDGPUGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM AMDGPUGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM AMDGPUGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM AMDGPUGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM AMDGPUGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM AMDGPUGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM AMDGPUGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM AMDGPUGenMCPseudoLowering.inc -gen-pseudo-lowering)
-- tablegen(LLVM AMDGPUGenRegisterBank.inc -gen-register-bank)
-- tablegen(LLVM AMDGPUGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM AMDGPUGenSearchableTables.inc -gen-searchable-tables)
-- tablegen(LLVM AMDGPUGenSubtargetInfo.inc -gen-subtarget)

local AMDGPU_TD = LLVM_LIB_DIR .. 'Target/AMDGPU/AMDGPU.td'
local AMDGPU_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_amdgpu = ninja.target('tablegen_amdgpu')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/AMDGPU' },
            flags = { '--write-if-changed' },
        })
    :src({
            AMDGPU_TD,
            cmd = '-gen-asm-matcher',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenAsmMatcher.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-asm-writer',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenAsmWriter.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-callingconv',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenCallingConv.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-dag-isel',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenDAGISel.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-disassembler',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenDisassemblerTables.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-instr-info',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenInstrInfo.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-emitter',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenMCCodeEmitter.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-pseudo-lowering',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenMCPseudoLowering.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-register-bank',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenRegisterBank.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-register-info',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenRegisterInfo.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-searchable-tables',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenSearchableTables.inc'
        },
        {
            AMDGPU_TD,
            cmd = '-gen-subtarget',
            output = AMDGPU_TD_OUTDIR .. 'AMDGPUGenSubtargetInfo.inc'
        })

-- set(LLVM_TARGET_DEFINITIONS AMDGPUGISel.td)
-- tablegen(LLVM AMDGPUGenGlobalISel.inc -gen-global-isel)
-- tablegen(LLVM AMDGPUGenPreLegalizeGICombiner.inc -gen-global-isel-combiner-matchtable -combiners="AMDGPUPreLegalizerCombiner")
-- tablegen(LLVM AMDGPUGenPostLegalizeGICombiner.inc -gen-global-isel-combiner-matchtable -combiners="AMDGPUPostLegalizerCombiner")
-- tablegen(LLVM AMDGPUGenRegBankGICombiner.inc -gen-global-isel-combiner-matchtable -combiners="AMDGPURegBankCombiner")

local AMDGPUGISEL_TD = LLVM_LIB_DIR .. 'Target/AMDGPU/AMDGPUGISel.td'
local AMDGPUGISEL_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_amdgpu_gisel = ninja.target('tablegen_amdgpu_gisel')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/AMDGPU' },
            flags = { '--write-if-changed' },
        })
    :src({
            AMDGPUGISEL_TD,
            cmd = '-gen-global-isel',
            output = AMDGPUGISEL_TD_OUTDIR .. 'AMDGPUGenGlobalISel.inc'
        },
        {
            AMDGPUGISEL_TD,
            cmd = '-gen-global-isel-combiner-matchtable -combiners=AMDGPUPreLegalizerCombiner',
            output = AMDGPUGISEL_TD_OUTDIR .. 'AMDGPUGenPreLegalizeGICombiner.inc'
        },
        {
            AMDGPUGISEL_TD,
            cmd = '-gen-global-isel-combiner-matchtable -combiners=AMDGPUPostLegalizerCombiner',
            output = AMDGPUGISEL_TD_OUTDIR .. 'AMDGPUGenPostLegalizeGICombiner.inc'
        },
        {
            AMDGPUGISEL_TD,
            cmd = '-gen-global-isel-combiner-matchtable -combiners=AMDGPURegBankCombiner',
            output = AMDGPUGISEL_TD_OUTDIR .. 'AMDGPUGenRegBankGICombiner.inc'
        })

-- set(LLVM_TARGET_DEFINITIONS R600.td)
-- tablegen(LLVM R600GenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM R600GenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM R600GenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM R600GenDFAPacketizer.inc -gen-dfa-packetizer)
-- tablegen(LLVM R600GenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM R600GenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM R600GenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM R600GenSubtargetInfo.inc -gen-subtarget)

local R600_TD = LLVM_LIB_DIR .. 'Target/AMDGPU/R600.td'
local R600_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_r600 = ninja.target('tablegen_r600')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/AMDGPU' },
            flags = { '--write-if-changed' },
        })
    :src({
            R600_TD,
            cmd = '-gen-asm-writer',
            output = R600_TD_OUTDIR .. 'R600GenAsmWriter.inc'
        },
        {
            R600_TD,
            cmd = '-gen-callingconv',
            output = R600_TD_OUTDIR .. 'R600GenCallingConv.inc'
        },
        {
            R600_TD,
            cmd = '-gen-dag-isel',
            output = R600_TD_OUTDIR .. 'R600GenDAGISel.inc'
        },
        {
            R600_TD,
            cmd = '-gen-dfa-packetizer',
            output = R600_TD_OUTDIR .. 'R600GenDFAPacketizer.inc'
        },
        {
            R600_TD,
            cmd = '-gen-instr-info',
            output = R600_TD_OUTDIR .. 'R600GenInstrInfo.inc'
        },
        {
            R600_TD,
            cmd = '-gen-emitter',
            output = R600_TD_OUTDIR .. 'R600GenMCCodeEmitter.inc'
        },
        {
            R600_TD,
            cmd = '-gen-register-info',
            output = R600_TD_OUTDIR .. 'R600GenRegisterInfo.inc'
        },
        {
            R600_TD,
            cmd = '-gen-subtarget',
            output = R600_TD_OUTDIR .. 'R600GenSubtargetInfo.inc'
        })

-- set(LLVM_TARGET_DEFINITIONS InstCombineTables.td)
-- tablegen(LLVM InstCombineTables.inc -gen-searchable-tables)
-- add_public_tablegen_target(InstCombineTableGen)

local INSTCOMBINE_TD = LLVM_LIB_DIR .. 'Target/AMDGPU/InstCombineTables.td'
local INSTCOMBINE_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_instcombine = ninja.target('tablegen_instcombine')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'Target/AMDGPU' },
            flags = { '--write-if-changed' },
        })
    :src({
        INSTCOMBINE_TD,
        cmd = '-gen-searchable-tables',
        output = INSTCOMBINE_TD_OUTDIR .. 'InstCombineTables.inc'
    })

local libtarget_amdgpu = ninja.target('libtarget_amdgpu')
    :type('static')
    :deps(llvm, tablegen_amdgpu, tablegen_amdgpu_gisel, tablegen_r600, tablegen_instcombine)
    :include_dir(LLVM_LIB_DIR .. 'Target/AMDGPU')
    :include_dir(AMDGPU_TD_OUTDIR)
    -- :include_dir(AMDGPUGISEL_TD_OUTDIR)
    -- :include_dir(R600_TD_OUTDIR)
    -- :include_dir(INSTCOMBINE_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/AMDGPU/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AMDGPU/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AMDGPU/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AMDGPU/MCA/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AMDGPU/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AMDGPU/TargetInfo/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AMDGPU/Utils/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS ARC.td)

-- tablegen(LLVM ARCGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM ARCGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM ARCGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM ARCGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM ARCGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM ARCGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM ARCGenSubtargetInfo.inc -gen-subtarget)

local ARC_TD = LLVM_LIB_DIR .. 'Target/ARC/ARC.td'
local ARC_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_arc = ninja.target('tablegen_arc')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/ARC' },
            flags = { '--write-if-changed' },
        })
    :src({
            ARC_TD,
            cmd = '-gen-asm-writer',
            output = ARC_TD_OUTDIR .. 'ARCGenAsmWriter.inc'
        },
        {
            ARC_TD,
            cmd = '-gen-callingconv',
            output = ARC_TD_OUTDIR .. 'ARCGenCallingConv.inc'
        },
        {
            ARC_TD,
            cmd = '-gen-dag-isel',
            output = ARC_TD_OUTDIR .. 'ARCGenDAGISel.inc'
        },
        {
            ARC_TD,
            cmd = '-gen-disassembler',
            output = ARC_TD_OUTDIR .. 'ARCGenDisassemblerTables.inc'
        },
        {
            ARC_TD,
            cmd = '-gen-instr-info',
            output = ARC_TD_OUTDIR .. 'ARCGenInstrInfo.inc'
        },
        {
            ARC_TD,
            cmd = '-gen-register-info',
            output = ARC_TD_OUTDIR .. 'ARCGenRegisterInfo.inc'
        },
        {
            ARC_TD,
            cmd = '-gen-subtarget',
            output = ARC_TD_OUTDIR .. 'ARCGenSubtargetInfo.inc'
        })

local libtarget_arc = ninja.target('libtarget_arc')
    :type('static')
    :deps(llvm, tablegen_arc)
    :include_dir(LLVM_LIB_DIR .. 'Target/ARC')
    :include_dir(ARC_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/ARC/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/ARC/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/ARC/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/ARC/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS AVR.td)

-- tablegen(LLVM AVRGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM AVRGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM AVRGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM AVRGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM AVRGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM AVRGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM AVRGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM AVRGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM AVRGenSubtargetInfo.inc -gen-subtarget)

local AVR_TD = LLVM_LIB_DIR .. 'Target/AVR/AVR.td'
local AVR_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_avr = ninja.target('tablegen_avr')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/AVR' },
            flags = { '--write-if-changed' },
        })
    :src({
            AVR_TD,
            cmd = '-gen-asm-matcher',
            output = AVR_TD_OUTDIR .. 'AVRGenAsmMatcher.inc'
        },
        {
            AVR_TD,
            cmd = '-gen-asm-writer',
            output = AVR_TD_OUTDIR .. 'AVRGenAsmWriter.inc'
        },
        {
            AVR_TD,
            cmd = '-gen-callingconv',
            output = AVR_TD_OUTDIR .. 'AVRGenCallingConv.inc'
        },
        {
            AVR_TD,
            cmd = '-gen-dag-isel',
            output = AVR_TD_OUTDIR .. 'AVRGenDAGISel.inc'
        },
        {
            AVR_TD,
            cmd = '-gen-disassembler',
            output = AVR_TD_OUTDIR .. 'AVRGenDisassemblerTables.inc'
        },
        {
            AVR_TD,
            cmd = '-gen-instr-info',
            output = AVR_TD_OUTDIR .. 'AVRGenInstrInfo.inc'
        },
        {
            AVR_TD,
            cmd = '-gen-emitter',
            output = AVR_TD_OUTDIR .. 'AVRGenMCCodeEmitter.inc'
        },
        {
            AVR_TD,
            cmd = '-gen-register-info',
            output = AVR_TD_OUTDIR .. 'AVRGenRegisterInfo.inc'
        },
        {
            AVR_TD,
            cmd = '-gen-subtarget',
            output = AVR_TD_OUTDIR .. 'AVRGenSubtargetInfo.inc'
        })

local libtarget_avr = ninja.target('libtarget_avr')
    :type('static')
    :deps(llvm, tablegen_avr)
    :include_dir(LLVM_LIB_DIR .. 'Target/AVR')
    :include_dir(AVR_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/AVR/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AVR/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AVR/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AVR/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/AVR/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS BPF.td)

-- tablegen(LLVM BPFGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM BPFGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM BPFGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM BPFGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM BPFGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM BPFGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM BPFGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM BPFGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM BPFGenSubtargetInfo.inc -gen-subtarget)

local BPF_TD = LLVM_LIB_DIR .. 'Target/BPF/BPF.td'
local BPF_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_bpf = ninja.target('tablegen_bpf')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/BPF' },
            flags = { '--write-if-changed' },
        })
    :src({
            BPF_TD,
            cmd = '-gen-asm-matcher',
            output = BPF_TD_OUTDIR .. 'BPFGenAsmMatcher.inc'
        },
        {
            BPF_TD,
            cmd = '-gen-asm-writer',
            output = BPF_TD_OUTDIR .. 'BPFGenAsmWriter.inc'
        },
        {
            BPF_TD,
            cmd = '-gen-callingconv',
            output = BPF_TD_OUTDIR .. 'BPFGenCallingConv.inc'
        },
        {
            BPF_TD,
            cmd = '-gen-dag-isel',
            output = BPF_TD_OUTDIR .. 'BPFGenDAGISel.inc'
        },
        {
            BPF_TD,
            cmd = '-gen-disassembler',
            output = BPF_TD_OUTDIR .. 'BPFGenDisassemblerTables.inc'
        },
        {
            BPF_TD,
            cmd = '-gen-instr-info',
            output = BPF_TD_OUTDIR .. 'BPFGenInstrInfo.inc'
        },
        {
            BPF_TD,
            cmd = '-gen-emitter',
            output = BPF_TD_OUTDIR .. 'BPFGenMCCodeEmitter.inc'
        },
        {
            BPF_TD,
            cmd = '-gen-register-info',
            output = BPF_TD_OUTDIR .. 'BPFGenRegisterInfo.inc'
        },
        {
            BPF_TD,
            cmd = '-gen-subtarget',
            output = BPF_TD_OUTDIR .. 'BPFGenSubtargetInfo.inc'
        })

local libtarget_bpf = ninja.target('libtarget_bpf')
    :type('static')
    :deps(llvm, tablegen_bpf)
    :include_dir(LLVM_LIB_DIR .. 'Target/BPF')
    :include_dir(BPF_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/BPF/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/BPF/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/BPF/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/BPF/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/BPF/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS CSKY.td)

-- tablegen(LLVM CSKYGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM CSKYGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM CSKYGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM CSKYGenCompressInstEmitter.inc -gen-compress-inst-emitter)
-- tablegen(LLVM CSKYGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM CSKYGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM CSKYGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM CSKYGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM CSKYGenMCPseudoLowering.inc -gen-pseudo-lowering)
-- tablegen(LLVM CSKYGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM CSKYGenSubtargetInfo.inc -gen-subtarget)

local CSKY_TD = LLVM_LIB_DIR .. 'Target/CSKY/CSKY.td'
local CSKY_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_csky = ninja.target('tablegen_csky')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/CSKY' },
            flags = { '--write-if-changed' },
        })
    :src({
            CSKY_TD,
            cmd = '-gen-asm-matcher',
            output = CSKY_TD_OUTDIR .. 'CSKYGenAsmMatcher.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-asm-writer',
            output = CSKY_TD_OUTDIR .. 'CSKYGenAsmWriter.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-callingconv',
            output = CSKY_TD_OUTDIR .. 'CSKYGenCallingConv.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-compress-inst-emitter',
            output = CSKY_TD_OUTDIR .. 'CSKYGenCompressInstEmitter.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-dag-isel',
            output = CSKY_TD_OUTDIR .. 'CSKYGenDAGISel.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-disassembler',
            output = CSKY_TD_OUTDIR .. 'CSKYGenDisassemblerTables.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-instr-info',
            output = CSKY_TD_OUTDIR .. 'CSKYGenInstrInfo.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-emitter',
            output = CSKY_TD_OUTDIR .. 'CSKYGenMCCodeEmitter.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-pseudo-lowering',
            output = CSKY_TD_OUTDIR .. 'CSKYGenMCPseudoLowering.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-register-info',
            output = CSKY_TD_OUTDIR .. 'CSKYGenRegisterInfo.inc'
        },
        {
            CSKY_TD,
            cmd = '-gen-subtarget',
            output = CSKY_TD_OUTDIR .. 'CSKYGenSubtargetInfo.inc'
        })

local libtarget_csky = ninja.target('libtarget_csky')
    :type('static')
    :deps(llvm, tablegen_csky)
    :include_dir(LLVM_LIB_DIR .. 'Target/CSKY')
    :include_dir(CSKY_TD_OUTDIR)
    :cxx_flags('/wd4715')
    :src(LLVM_LIB_DIR .. 'Target/CSKY/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/CSKY/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/CSKY/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/CSKY/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/CSKY/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS DirectX.td)

-- tablegen(LLVM DirectXGenSubtargetInfo.inc -gen-subtarget)
-- tablegen(LLVM DirectXGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM DirectXGenRegisterInfo.inc -gen-register-info)

local DIRECTX_TD = LLVM_LIB_DIR .. 'Target/DirectX/DirectX.td'
local DIRECTX_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_directx = ninja.target('tablegen_directx')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/DirectX' },
            flags = { '--write-if-changed' },
        })
    :src({
            DIRECTX_TD,
            cmd = '-gen-subtarget',
            output = DIRECTX_TD_OUTDIR .. 'DirectXGenSubtargetInfo.inc'
        },
        {
            DIRECTX_TD,
            cmd = '-gen-instr-info',
            output = DIRECTX_TD_OUTDIR .. 'DirectXGenInstrInfo.inc'
        },
        {
            DIRECTX_TD,
            cmd = '-gen-register-info',
            output = DIRECTX_TD_OUTDIR .. 'DirectXGenRegisterInfo.inc'
        })

-- set(LLVM_TARGET_DEFINITIONS DXIL.td)
-- tablegen(LLVM DXILOperation.inc -gen-dxil-operation)

local DXIL_TD = LLVM_LIB_DIR .. 'Target/DirectX/DXIL.td'
local DXIL_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_dxil = ninja.target('tablegen_dxil')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/DirectX' },
            flags = { '--write-if-changed' },
        })
    :src({
        DXIL_TD,
        cmd = '-gen-dxil-operation',
        output = DXIL_TD_OUTDIR .. 'DXILOperation.inc'
    })

local libtarget_directx = ninja.target('libtarget_directx')
    :type('static')
    :deps(llvm, tablegen_directx, tablegen_dxil)
    :include_dir(LLVM_LIB_DIR .. 'Target/DirectX')
    :include_dir(DIRECTX_TD_OUTDIR)
    :include_dir(DXIL_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/DirectX/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/DirectX/DXILWriter/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/DirectX/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/DirectX/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS Hexagon.td)

-- tablegen(LLVM HexagonGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM HexagonGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM HexagonGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM HexagonGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM HexagonGenDFAPacketizer.inc -gen-dfa-packetizer)
-- tablegen(LLVM HexagonGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM HexagonGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM HexagonGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM HexagonGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM HexagonGenSubtargetInfo.inc -gen-subtarget)

local HEXAGON_TD = LLVM_LIB_DIR .. 'Target/Hexagon/Hexagon.td'
local HEXAGON_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_hexagon = ninja.target('tablegen_hexagon')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/Hexagon' },
            flags = { '--write-if-changed' },
        })
    :src({
            HEXAGON_TD,
            cmd = '-gen-asm-matcher',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenAsmMatcher.inc'
        },
        {
            HEXAGON_TD,
            cmd = '-gen-asm-writer',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenAsmWriter.inc'
        },
        {
            HEXAGON_TD,
            cmd = '-gen-callingconv',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenCallingConv.inc'
        },
        {
            HEXAGON_TD,
            cmd = '-gen-dag-isel',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenDAGISel.inc'
        },
        {
            HEXAGON_TD,
            cmd = '-gen-dfa-packetizer',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenDFAPacketizer.inc'
        },
        {
            HEXAGON_TD,
            cmd = '-gen-disassembler',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenDisassemblerTables.inc'
        },
        {
            HEXAGON_TD,
            cmd = '-gen-instr-info',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenInstrInfo.inc'
        },
        {
            HEXAGON_TD,
            cmd = '-gen-emitter',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenMCCodeEmitter.inc'
        },
        {
            HEXAGON_TD,
            cmd = '-gen-register-info',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenRegisterInfo.inc'
        },
        {
            HEXAGON_TD,
            cmd = '-gen-subtarget',
            output = HEXAGON_TD_OUTDIR .. 'HexagonGenSubtargetInfo.inc'
        })

local libtarget_hexagon = ninja.target('libtarget_hexagon')
    :type('static')
    :deps(llvm, tablegen_hexagon)
    :include_dir(LLVM_LIB_DIR .. 'Target/Hexagon')
    :include_dir(HEXAGON_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/Hexagon/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Hexagon/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Hexagon/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Hexagon/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Hexagon/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS Lanai.td)

-- tablegen(LLVM LanaiGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM LanaiGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM LanaiGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM LanaiGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM LanaiGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM LanaiGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM LanaiGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM LanaiGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM LanaiGenSubtargetInfo.inc -gen-subtarget)

local LANAI_TD = LLVM_LIB_DIR .. 'Target/Lanai/Lanai.td'
local LANAI_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_lanai = ninja.target('tablegen_lanai')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/Lanai' },
            flags = { '--write-if-changed' },
        })
    :src({
            LANAI_TD,
            cmd = '-gen-asm-matcher',
            output = LANAI_TD_OUTDIR .. 'LanaiGenAsmMatcher.inc'
        },
        {
            LANAI_TD,
            cmd = '-gen-asm-writer',
            output = LANAI_TD_OUTDIR .. 'LanaiGenAsmWriter.inc'
        },
        {
            LANAI_TD,
            cmd = '-gen-callingconv',
            output = LANAI_TD_OUTDIR .. 'LanaiGenCallingConv.inc'
        },
        {
            LANAI_TD,
            cmd = '-gen-dag-isel',
            output = LANAI_TD_OUTDIR .. 'LanaiGenDAGISel.inc'
        },
        {
            LANAI_TD,
            cmd = '-gen-disassembler',
            output = LANAI_TD_OUTDIR .. 'LanaiGenDisassemblerTables.inc'
        },
        {
            LANAI_TD,
            cmd = '-gen-instr-info',
            output = LANAI_TD_OUTDIR .. 'LanaiGenInstrInfo.inc'
        },
        {
            LANAI_TD,
            cmd = '-gen-emitter',
            output = LANAI_TD_OUTDIR .. 'LanaiGenMCCodeEmitter.inc'
        },
        {
            LANAI_TD,
            cmd = '-gen-register-info',
            output = LANAI_TD_OUTDIR .. 'LanaiGenRegisterInfo.inc'
        },
        {
            LANAI_TD,
            cmd = '-gen-subtarget',
            output = LANAI_TD_OUTDIR .. 'LanaiGenSubtargetInfo.inc'
        })

local libtarget_lanai = ninja.target('libtarget_lanai')
    :type('static')
    :deps(llvm, tablegen_lanai)
    :include_dir(LLVM_LIB_DIR .. 'Target/Lanai')
    :include_dir(LANAI_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/Lanai/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Lanai/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Lanai/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Lanai/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Lanai/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS LoongArch.td)

-- tablegen(LLVM LoongArchGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM LoongArchGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM LoongArchGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM LoongArchGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM LoongArchGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM LoongArchGenMCPseudoLowering.inc -gen-pseudo-lowering)
-- tablegen(LLVM LoongArchGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM LoongArchGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM LoongArchGenSubtargetInfo.inc -gen-subtarget)

local LOONGARCH_TD = LLVM_LIB_DIR .. 'Target/LoongArch/LoongArch.td'
local LOONGARCH_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_loongarch = ninja.target('tablegen_loongarch')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/LoongArch' },
            flags = { '--write-if-changed' },
        })
    :src({
            LOONGARCH_TD,
            cmd = '-gen-asm-matcher',
            output = LOONGARCH_TD_OUTDIR .. 'LoongArchGenAsmMatcher.inc'
        },
        {
            LOONGARCH_TD,
            cmd = '-gen-asm-writer',
            output = LOONGARCH_TD_OUTDIR .. 'LoongArchGenAsmWriter.inc'
        },
        {
            LOONGARCH_TD,
            cmd = '-gen-dag-isel',
            output = LOONGARCH_TD_OUTDIR .. 'LoongArchGenDAGISel.inc'
        },
        {
            LOONGARCH_TD,
            cmd = '-gen-disassembler',
            output = LOONGARCH_TD_OUTDIR .. 'LoongArchGenDisassemblerTables.inc'
        },
        {
            LOONGARCH_TD,
            cmd = '-gen-instr-info',
            output = LOONGARCH_TD_OUTDIR .. 'LoongArchGenInstrInfo.inc'
        },
        {
            LOONGARCH_TD,
            cmd = '-gen-pseudo-lowering',
            output = LOONGARCH_TD_OUTDIR .. 'LoongArchGenMCPseudoLowering.inc'
        },
        {
            LOONGARCH_TD,
            cmd = '-gen-emitter',
            output = LOONGARCH_TD_OUTDIR .. 'LoongArchGenMCCodeEmitter.inc'
        },
        {
            LOONGARCH_TD,
            cmd = '-gen-register-info',
            output = LOONGARCH_TD_OUTDIR .. 'LoongArchGenRegisterInfo.inc'
        },
        {
            LOONGARCH_TD,
            cmd = '-gen-subtarget',
            output = LOONGARCH_TD_OUTDIR .. 'LoongArchGenSubtargetInfo.inc'
        })

local libtarget_loongarch = ninja.target('libtarget_loongarch')
    :type('static')
    :deps(llvm, tablegen_loongarch)
    :include_dir(LLVM_LIB_DIR .. 'Target/LoongArch')
    :include_dir(LOONGARCH_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/LoongArch/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/LoongArch/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/LoongArch/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/LoongArch/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/LoongArch/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS M68k.td)

-- tablegen(LLVM M68kGenGlobalISel.inc       -gen-global-isel)
-- tablegen(LLVM M68kGenRegisterInfo.inc     -gen-register-info)
-- tablegen(LLVM M68kGenRegisterBank.inc     -gen-register-bank)
-- tablegen(LLVM M68kGenInstrInfo.inc        -gen-instr-info)
-- tablegen(LLVM M68kGenSubtargetInfo.inc    -gen-subtarget)
-- tablegen(LLVM M68kGenMCCodeEmitter.inc    -gen-emitter)
-- tablegen(LLVM M68kGenMCPseudoLowering.inc -gen-pseudo-lowering)
-- tablegen(LLVM M68kGenDAGISel.inc          -gen-dag-isel)
-- tablegen(LLVM M68kGenCallingConv.inc      -gen-callingconv)
-- tablegen(LLVM M68kGenAsmWriter.inc        -gen-asm-writer)
-- tablegen(LLVM M68kGenAsmMatcher.inc       -gen-asm-matcher)
-- tablegen(LLVM M68kGenDisassemblerTable.inc -gen-disassembler)

local M68K_TD = LLVM_LIB_DIR .. 'Target/M68k/M68k.td'
local M68K_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_m68k = ninja.target('tablegen_m68k')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/M68k' },
            flags = { '--write-if-changed' },
        })
    :src({
            M68K_TD,
            cmd = '-gen-global-isel',
            output = M68K_TD_OUTDIR .. 'M68kGenGlobalISel.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-register-info',
            output = M68K_TD_OUTDIR .. 'M68kGenRegisterInfo.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-register-bank',
            output = M68K_TD_OUTDIR .. 'M68kGenRegisterBank.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-instr-info',
            output = M68K_TD_OUTDIR .. 'M68kGenInstrInfo.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-subtarget',
            output = M68K_TD_OUTDIR .. 'M68kGenSubtargetInfo.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-emitter',
            output = M68K_TD_OUTDIR .. 'M68kGenMCCodeEmitter.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-pseudo-lowering',
            output = M68K_TD_OUTDIR .. 'M68kGenMCPseudoLowering.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-dag-isel',
            output = M68K_TD_OUTDIR .. 'M68kGenDAGISel.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-callingconv',
            output = M68K_TD_OUTDIR .. 'M68kGenCallingConv.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-asm-writer',
            output = M68K_TD_OUTDIR .. 'M68kGenAsmWriter.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-asm-matcher',
            output = M68K_TD_OUTDIR .. 'M68kGenAsmMatcher.inc'
        },
        {
            M68K_TD,
            cmd = '-gen-disassembler',
            output = M68K_TD_OUTDIR .. 'M68kGenDisassemblerTable.inc'
        })

local libtarget_m68k = ninja.target('libtarget_m68k')
    :type('static')
    :deps(llvm, tablegen_m68k)
    :include_dir(LLVM_LIB_DIR .. 'Target/M68k')
    :include_dir(M68K_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/M68k/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/M68k/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/M68k/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/M68k/GISel/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/M68k/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/M68k/TargetInfo/*.cpp')


-- set(LLVM_TARGET_DEFINITIONS Mips.td)

-- tablegen(LLVM MipsGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM MipsGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM MipsGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM MipsGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM MipsGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM MipsGenFastISel.inc -gen-fast-isel)
-- tablegen(LLVM MipsGenGlobalISel.inc -gen-global-isel)
-- tablegen(LLVM MipsGenPostLegalizeGICombiner.inc -gen-global-isel-combiner-matchtable -combiners="MipsPostLegalizerCombiner")
-- tablegen(LLVM MipsGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM MipsGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM MipsGenMCPseudoLowering.inc -gen-pseudo-lowering)
-- tablegen(LLVM MipsGenRegisterBank.inc -gen-register-bank)
-- tablegen(LLVM MipsGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM MipsGenSubtargetInfo.inc -gen-subtarget)
-- tablegen(LLVM MipsGenExegesis.inc -gen-exegesis)

local MIPS_TD = LLVM_LIB_DIR .. 'Target/Mips/Mips.td'
local MIPS_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_mips = ninja.target('tablegen_mips')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/Mips' },
            flags = { '--write-if-changed' },
        })
    :src({
            MIPS_TD,
            cmd = '-gen-asm-matcher',
            output = MIPS_TD_OUTDIR .. 'MipsGenAsmMatcher.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-asm-writer',
            output = MIPS_TD_OUTDIR .. 'MipsGenAsmWriter.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-callingconv',
            output = MIPS_TD_OUTDIR .. 'MipsGenCallingConv.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-dag-isel',
            output = MIPS_TD_OUTDIR .. 'MipsGenDAGISel.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-disassembler',
            output = MIPS_TD_OUTDIR .. 'MipsGenDisassemblerTables.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-fast-isel',
            output = MIPS_TD_OUTDIR .. 'MipsGenFastISel.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-global-isel',
            output = MIPS_TD_OUTDIR .. 'MipsGenGlobalISel.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-global-isel-combiner-matchtable -combiners=MipsPostLegalizerCombiner',
            output = MIPS_TD_OUTDIR .. 'MipsGenPostLegalizeGICombiner.inc',
            combiners = 'MipsPostLegalizerCombiner'
        },
        {
            MIPS_TD,
            cmd = '-gen-instr-info',
            output = MIPS_TD_OUTDIR .. 'MipsGenInstrInfo.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-emitter',
            output = MIPS_TD_OUTDIR .. 'MipsGenMCCodeEmitter.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-pseudo-lowering',
            output = MIPS_TD_OUTDIR .. 'MipsGenMCPseudoLowering.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-register-bank',
            output = MIPS_TD_OUTDIR .. 'MipsGenRegisterBank.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-register-info',
            output = MIPS_TD_OUTDIR .. 'MipsGenRegisterInfo.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-subtarget',
            output = MIPS_TD_OUTDIR .. 'MipsGenSubtargetInfo.inc'
        },
        {
            MIPS_TD,
            cmd = '-gen-exegesis',
            output = MIPS_TD_OUTDIR .. 'MipsGenExegesis.inc'
        })

local libtarget_mips = ninja.target('libtarget_mips')
    :type('static')
    :deps(llvm, tablegen_mips)
    :include_dir(LLVM_LIB_DIR .. 'Target/Mips')
    :include_dir(MIPS_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/Mips/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Mips/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Mips/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Mips/GISel/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Mips/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Mips/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS MSP430.td)

-- tablegen(LLVM MSP430GenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM MSP430GenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM MSP430GenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM MSP430GenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM MSP430GenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM MSP430GenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM MSP430GenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM MSP430GenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM MSP430GenSubtargetInfo.inc -gen-subtarget)

local MSP430_TD = LLVM_LIB_DIR .. 'Target/MSP430/MSP430.td'
local MSP430_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_msp430 = ninja.target('tablegen_msp430')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/MSP430' },
            flags = { '--write-if-changed' },
        })
    :src({
            MSP430_TD,
            cmd = '-gen-asm-matcher',
            output = MSP430_TD_OUTDIR .. 'MSP430GenAsmMatcher.inc'
        },
        {
            MSP430_TD,
            cmd = '-gen-asm-writer',
            output = MSP430_TD_OUTDIR .. 'MSP430GenAsmWriter.inc'
        },
        {
            MSP430_TD,
            cmd = '-gen-callingconv',
            output = MSP430_TD_OUTDIR .. 'MSP430GenCallingConv.inc'
        },
        {
            MSP430_TD,
            cmd = '-gen-dag-isel',
            output = MSP430_TD_OUTDIR .. 'MSP430GenDAGISel.inc'
        },
        {
            MSP430_TD,
            cmd = '-gen-disassembler',
            output = MSP430_TD_OUTDIR .. 'MSP430GenDisassemblerTables.inc'
        },
        {
            MSP430_TD,
            cmd = '-gen-instr-info',
            output = MSP430_TD_OUTDIR .. 'MSP430GenInstrInfo.inc'
        },
        {
            MSP430_TD,
            cmd = '-gen-emitter',
            output = MSP430_TD_OUTDIR .. 'MSP430GenMCCodeEmitter.inc'
        },
        {
            MSP430_TD,
            cmd = '-gen-register-info',
            output = MSP430_TD_OUTDIR .. 'MSP430GenRegisterInfo.inc'
        },
        {
            MSP430_TD,
            cmd = '-gen-subtarget',
            output = MSP430_TD_OUTDIR .. 'MSP430GenSubtargetInfo.inc'
        })

local libtarget_msp430 = ninja.target('libtarget_msp430')
    :type('static')
    :deps(llvm, tablegen_msp430)
    :include_dir(LLVM_LIB_DIR .. 'Target/MSP430')
    :include_dir(MSP430_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/MSP430/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/MSP430/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/MSP430/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/MSP430/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/MSP430/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS NVPTX.td)

-- tablegen(LLVM NVPTXGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM NVPTXGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM NVPTXGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM NVPTXGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM NVPTXGenSubtargetInfo.inc -gen-subtarget)

local NVPTX_TD = LLVM_LIB_DIR .. 'Target/NVPTX/NVPTX.td'
local NVPTX_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_nvptx = ninja.target('tablegen_nvptx')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/NVPTX' },
            flags = { '--write-if-changed' },
        })
    :src({
            NVPTX_TD,
            cmd = '-gen-asm-writer',
            output = NVPTX_TD_OUTDIR .. 'NVPTXGenAsmWriter.inc'
        },
        {
            NVPTX_TD,
            cmd = '-gen-dag-isel',
            output = NVPTX_TD_OUTDIR .. 'NVPTXGenDAGISel.inc'
        },
        {
            NVPTX_TD,
            cmd = '-gen-instr-info',
            output = NVPTX_TD_OUTDIR .. 'NVPTXGenInstrInfo.inc'
        },
        {
            NVPTX_TD,
            cmd = '-gen-register-info',
            output = NVPTX_TD_OUTDIR .. 'NVPTXGenRegisterInfo.inc'
        },
        {
            NVPTX_TD,
            cmd = '-gen-subtarget',
            output = NVPTX_TD_OUTDIR .. 'NVPTXGenSubtargetInfo.inc'
        })

local libtarget_nvptx = ninja.target('libtarget_nvptx')
    :type('static')
    :deps(llvm, tablegen_nvptx)
    :include_dir(LLVM_LIB_DIR .. 'Target/NVPTX')
    :include_dir(NVPTX_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/NVPTX/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/NVPTX/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/NVPTX/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS PPC.td)

-- tablegen(LLVM PPCGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM PPCGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM PPCGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM PPCGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM PPCGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM PPCGenFastISel.inc -gen-fast-isel)
-- tablegen(LLVM PPCGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM PPCGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM PPCGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM PPCGenSubtargetInfo.inc -gen-subtarget)
-- tablegen(LLVM PPCGenExegesis.inc -gen-exegesis)
-- tablegen(LLVM PPCGenRegisterBank.inc -gen-register-bank)
-- tablegen(LLVM PPCGenGlobalISel.inc -gen-global-isel)

local PPC_TD = LLVM_LIB_DIR .. 'Target/PowerPC/PPC.td'
local PPC_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_ppc = ninja.target('tablegen_ppc')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/PowerPC' },
            flags = { '--write-if-changed' },
        })
    :src({
            PPC_TD,
            cmd = '-gen-asm-matcher',
            output = PPC_TD_OUTDIR .. 'PPCGenAsmMatcher.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-asm-writer',
            output = PPC_TD_OUTDIR .. 'PPCGenAsmWriter.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-callingconv',
            output = PPC_TD_OUTDIR .. 'PPCGenCallingConv.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-dag-isel',
            output = PPC_TD_OUTDIR .. 'PPCGenDAGISel.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-disassembler',
            output = PPC_TD_OUTDIR .. 'PPCGenDisassemblerTables.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-fast-isel',
            output = PPC_TD_OUTDIR .. 'PPCGenFastISel.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-instr-info',
            output = PPC_TD_OUTDIR .. 'PPCGenInstrInfo.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-emitter',
            output = PPC_TD_OUTDIR .. 'PPCGenMCCodeEmitter.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-register-info',
            output = PPC_TD_OUTDIR .. 'PPCGenRegisterInfo.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-subtarget',
            output = PPC_TD_OUTDIR .. 'PPCGenSubtargetInfo.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-exegesis',
            output = PPC_TD_OUTDIR .. 'PPCGenExegesis.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-register-bank',
            output = PPC_TD_OUTDIR .. 'PPCGenRegisterBank.inc'
        },
        {
            PPC_TD,
            cmd = '-gen-global-isel',
            output = PPC_TD_OUTDIR .. 'PPCGenGlobalISel.inc'
        })

local libtarget_ppc = ninja.target('libtarget_ppc')
    :type('static')
    :deps(llvm, tablegen_ppc)
    :include_dir(LLVM_LIB_DIR .. 'Target/PowerPC')
    :include_dir(PPC_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/PowerPC/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/PowerPC/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/PowerPC/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/PowerPC/GISel/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/PowerPC/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/PowerPC/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS RISCV.td)

-- tablegen(LLVM RISCVGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM RISCVGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM RISCVGenCompressInstEmitter.inc -gen-compress-inst-emitter)
-- tablegen(LLVM RISCVGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM RISCVGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM RISCVGenGlobalISel.inc -gen-global-isel)
-- tablegen(LLVM RISCVGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM RISCVGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM RISCVGenMCPseudoLowering.inc -gen-pseudo-lowering)
-- tablegen(LLVM RISCVGenRegisterBank.inc -gen-register-bank)
-- tablegen(LLVM RISCVGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM RISCVGenSearchableTables.inc -gen-searchable-tables)
-- tablegen(LLVM RISCVGenSubtargetInfo.inc -gen-subtarget)

local RISCV_TD = LLVM_LIB_DIR .. 'Target/RISCV/RISCV.td'
local RISCV_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_riscv = ninja.target('tablegen_riscv')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/RISCV' },
            flags = { '--write-if-changed' },
        })
    :src({
            RISCV_TD,
            cmd = '-gen-asm-matcher',
            output = RISCV_TD_OUTDIR .. 'RISCVGenAsmMatcher.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-asm-writer',
            output = RISCV_TD_OUTDIR .. 'RISCVGenAsmWriter.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-compress-inst-emitter',
            output = RISCV_TD_OUTDIR .. 'RISCVGenCompressInstEmitter.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-dag-isel',
            output = RISCV_TD_OUTDIR .. 'RISCVGenDAGISel.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-disassembler',
            output = RISCV_TD_OUTDIR .. 'RISCVGenDisassemblerTables.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-global-isel',
            output = RISCV_TD_OUTDIR .. 'RISCVGenGlobalISel.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-instr-info',
            output = RISCV_TD_OUTDIR .. 'RISCVGenInstrInfo.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-emitter',
            output = RISCV_TD_OUTDIR .. 'RISCVGenMCCodeEmitter.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-pseudo-lowering',
            output = RISCV_TD_OUTDIR .. 'RISCVGenMCPseudoLowering.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-register-bank',
            output = RISCV_TD_OUTDIR .. 'RISCVGenRegisterBank.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-register-info',
            output = RISCV_TD_OUTDIR .. 'RISCVGenRegisterInfo.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-searchable-tables',
            output = RISCV_TD_OUTDIR .. 'RISCVGenSearchableTables.inc'
        },
        {
            RISCV_TD,
            cmd = '-gen-subtarget',
            output = RISCV_TD_OUTDIR .. 'RISCVGenSubtargetInfo.inc'
        })

local libtarget_riscv = ninja.target('libtarget_riscv')
    :type('static')
    :deps(llvm, tablegen_riscv)
    :include_dir(LLVM_LIB_DIR .. 'Target/RISCV')
    :include_dir(RISCV_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/RISCV/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/RISCV/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/RISCV/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/RISCV/GISel/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/RISCV/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/RISCV/MCA/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/RISCV/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS Sparc.td)

-- tablegen(LLVM SparcGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM SparcGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM SparcGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM SparcGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM SparcGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM SparcGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM SparcGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM SparcGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM SparcGenSubtargetInfo.inc -gen-subtarget)

local SPARC_TD = LLVM_LIB_DIR .. 'Target/Sparc/Sparc.td'
local SPARC_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_sparc = ninja.target('tablegen_sparc')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/Sparc' },
            flags = { '--write-if-changed' },
        })
    :src({
            SPARC_TD,
            cmd = '-gen-asm-matcher',
            output = SPARC_TD_OUTDIR .. 'SparcGenAsmMatcher.inc'
        },
        {
            SPARC_TD,
            cmd = '-gen-asm-writer',
            output = SPARC_TD_OUTDIR .. 'SparcGenAsmWriter.inc'
        },
        {
            SPARC_TD,
            cmd = '-gen-callingconv',
            output = SPARC_TD_OUTDIR .. 'SparcGenCallingConv.inc'
        },
        {
            SPARC_TD,
            cmd = '-gen-dag-isel',
            output = SPARC_TD_OUTDIR .. 'SparcGenDAGISel.inc'
        },
        {
            SPARC_TD,
            cmd = '-gen-disassembler',
            output = SPARC_TD_OUTDIR .. 'SparcGenDisassemblerTables.inc'
        },
        {
            SPARC_TD,
            cmd = '-gen-instr-info',
            output = SPARC_TD_OUTDIR .. 'SparcGenInstrInfo.inc'
        },
        {
            SPARC_TD,
            cmd = '-gen-emitter',
            output = SPARC_TD_OUTDIR .. 'SparcGenMCCodeEmitter.inc'
        },
        {
            SPARC_TD,
            cmd = '-gen-register-info',
            output = SPARC_TD_OUTDIR .. 'SparcGenRegisterInfo.inc'
        },
        {
            SPARC_TD,
            cmd = '-gen-subtarget',
            output = SPARC_TD_OUTDIR .. 'SparcGenSubtargetInfo.inc'
        })

local libtarget_sparc = ninja.target('libtarget_sparc')
    :type('static')
    :deps(llvm, tablegen_sparc)
    :include_dir(LLVM_LIB_DIR .. 'Target/Sparc')
    :include_dir(SPARC_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/Sparc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Sparc/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Sparc/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Sparc/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Sparc/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS SPIRV.td)

-- tablegen(LLVM SPIRVGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM SPIRVGenGlobalISel.inc -gen-global-isel)
-- tablegen(LLVM SPIRVGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM SPIRVGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM SPIRVGenRegisterBank.inc -gen-register-bank)
-- tablegen(LLVM SPIRVGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM SPIRVGenSubtargetInfo.inc -gen-subtarget)
-- tablegen(LLVM SPIRVGenTables.inc -gen-searchable-tables)

local SPIRV_TD = LLVM_LIB_DIR .. 'Target/SPIRV/SPIRV.td'
local SPIRV_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_spirv = ninja.target('tablegen_spirv')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/SPIRV' },
            flags = { '--write-if-changed' },
        })
    :src({
            SPIRV_TD,
            cmd = '-gen-asm-writer',
            output = SPIRV_TD_OUTDIR .. 'SPIRVGenAsmWriter.inc'
        },
        {
            SPIRV_TD,
            cmd = '-gen-global-isel',
            output = SPIRV_TD_OUTDIR .. 'SPIRVGenGlobalISel.inc'
        },
        {
            SPIRV_TD,
            cmd = '-gen-instr-info',
            output = SPIRV_TD_OUTDIR .. 'SPIRVGenInstrInfo.inc'
        },
        {
            SPIRV_TD,
            cmd = '-gen-emitter',
            output = SPIRV_TD_OUTDIR .. 'SPIRVGenMCCodeEmitter.inc'
        },
        {
            SPIRV_TD,
            cmd = '-gen-register-bank',
            output = SPIRV_TD_OUTDIR .. 'SPIRVGenRegisterBank.inc'
        },
        {
            SPIRV_TD,
            cmd = '-gen-register-info',
            output = SPIRV_TD_OUTDIR .. 'SPIRVGenRegisterInfo.inc'
        },
        {
            SPIRV_TD,
            cmd = '-gen-subtarget',
            output = SPIRV_TD_OUTDIR .. 'SPIRVGenSubtargetInfo.inc'
        },
        {
            SPIRV_TD,
            cmd = '-gen-searchable-tables',
            output = SPIRV_TD_OUTDIR .. 'SPIRVGenTables.inc'
        })

local libtarget_spirv = ninja.target('libtarget_spirv')
    :type('static')
    :deps(llvm, tablegen_spirv)
    :include_dir(LLVM_LIB_DIR .. 'Target/SPIRV')
    :include_dir(SPIRV_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/SPIRV/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/SPIRV/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/SPIRV/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS SystemZ.td)

-- tablegen(LLVM SystemZGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM SystemZGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM SystemZGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM SystemZGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM SystemZGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM SystemZGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM SystemZGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM SystemZGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM SystemZGenSubtargetInfo.inc -gen-subtarget)

local SYSTEMZ_TD = LLVM_LIB_DIR .. 'Target/SystemZ/SystemZ.td'
local SYSTEMZ_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_systemz = ninja.target('tablegen_systemz')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/SystemZ' },
            flags = { '--write-if-changed' },
        })
    :src({
            SYSTEMZ_TD,
            cmd = '-gen-asm-matcher',
            output = SYSTEMZ_TD_OUTDIR .. 'SystemZGenAsmMatcher.inc'
        },
        {
            SYSTEMZ_TD,
            cmd = '-gen-asm-writer',
            output = SYSTEMZ_TD_OUTDIR .. 'SystemZGenAsmWriter.inc'
        },
        {
            SYSTEMZ_TD,
            cmd = '-gen-callingconv',
            output = SYSTEMZ_TD_OUTDIR .. 'SystemZGenCallingConv.inc'
        },
        {
            SYSTEMZ_TD,
            cmd = '-gen-dag-isel',
            output = SYSTEMZ_TD_OUTDIR .. 'SystemZGenDAGISel.inc'
        },
        {
            SYSTEMZ_TD,
            cmd = '-gen-disassembler',
            output = SYSTEMZ_TD_OUTDIR .. 'SystemZGenDisassemblerTables.inc'
        },
        {
            SYSTEMZ_TD,
            cmd = '-gen-instr-info',
            output = SYSTEMZ_TD_OUTDIR .. 'SystemZGenInstrInfo.inc'
        },
        {
            SYSTEMZ_TD,
            cmd = '-gen-emitter',
            output = SYSTEMZ_TD_OUTDIR .. 'SystemZGenMCCodeEmitter.inc'
        },
        {
            SYSTEMZ_TD,
            cmd = '-gen-register-info',
            output = SYSTEMZ_TD_OUTDIR .. 'SystemZGenRegisterInfo.inc'
        },
        {
            SYSTEMZ_TD,
            cmd = '-gen-subtarget',
            output = SYSTEMZ_TD_OUTDIR .. 'SystemZGenSubtargetInfo.inc'
        })

local libtarget_systemz = ninja.target('libtarget_systemz')
    :type('static')
    :deps(llvm, tablegen_systemz)
    :include_dir(LLVM_LIB_DIR .. 'Target/SystemZ')
    :include_dir(SYSTEMZ_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/SystemZ/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/SystemZ/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/SystemZ/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/SystemZ/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/SystemZ/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS VE.td)

-- tablegen(LLVM VEGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM VEGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM VEGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM VEGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM VEGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM VEGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM VEGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM VEGenSubtargetInfo.inc -gen-subtarget)
-- tablegen(LLVM VEGenCallingConv.inc -gen-callingconv)

local VE_TD = LLVM_LIB_DIR .. 'Target/VE/VE.td'
local VE_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_ve = ninja.target('tablegen_ve')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/VE' },
            flags = { '--write-if-changed' },
        })
    :src({
            VE_TD,
            cmd = '-gen-register-info',
            output = VE_TD_OUTDIR .. 'VEGenRegisterInfo.inc'
        },
        {
            VE_TD,
            cmd = '-gen-instr-info',
            output = VE_TD_OUTDIR .. 'VEGenInstrInfo.inc'
        },
        {
            VE_TD,
            cmd = '-gen-disassembler',
            output = VE_TD_OUTDIR .. 'VEGenDisassemblerTables.inc'
        },
        {
            VE_TD,
            cmd = '-gen-emitter',
            output = VE_TD_OUTDIR .. 'VEGenMCCodeEmitter.inc'
        },
        {
            VE_TD,
            cmd = '-gen-asm-writer',
            output = VE_TD_OUTDIR .. 'VEGenAsmWriter.inc'
        },
        {
            VE_TD,
            cmd = '-gen-asm-matcher',
            output = VE_TD_OUTDIR .. 'VEGenAsmMatcher.inc'
        },
        {
            VE_TD,
            cmd = '-gen-dag-isel',
            output = VE_TD_OUTDIR .. 'VEGenDAGISel.inc'
        },
        {
            VE_TD,
            cmd = '-gen-subtarget',
            output = VE_TD_OUTDIR .. 'VEGenSubtargetInfo.inc'
        },
        {
            VE_TD,
            cmd = '-gen-callingconv',
            output = VE_TD_OUTDIR .. 'VEGenCallingConv.inc'
        })

local libtarget_ve = ninja.target('libtarget_ve')
    :type('static')
    :deps(llvm, tablegen_ve)
    :include_dir(LLVM_LIB_DIR .. 'Target/VE')
    :include_dir(VE_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/VE/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/VE/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/VE/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/VE/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/VE/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS WebAssembly.td)

-- tablegen(LLVM WebAssemblyGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM WebAssemblyGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM WebAssemblyGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM WebAssemblyGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM WebAssemblyGenFastISel.inc -gen-fast-isel)
-- tablegen(LLVM WebAssemblyGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM WebAssemblyGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM WebAssemblyGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM WebAssemblyGenSubtargetInfo.inc -gen-subtarget)

local WEBASSEMBLY_TD = LLVM_LIB_DIR .. 'Target/WebAssembly/WebAssembly.td'
local WEBASSEMBLY_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_webassembly = ninja.target('tablegen_webassembly')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/WebAssembly' },
            flags = { '--write-if-changed' },
        })
    :src({
            WEBASSEMBLY_TD,
            cmd = '-gen-asm-matcher',
            output = WEBASSEMBLY_TD_OUTDIR .. 'WebAssemblyGenAsmMatcher.inc'
        },
        {
            WEBASSEMBLY_TD,
            cmd = '-gen-asm-writer',
            output = WEBASSEMBLY_TD_OUTDIR .. 'WebAssemblyGenAsmWriter.inc'
        },
        {
            WEBASSEMBLY_TD,
            cmd = '-gen-dag-isel',
            output = WEBASSEMBLY_TD_OUTDIR .. 'WebAssemblyGenDAGISel.inc'
        },
        {
            WEBASSEMBLY_TD,
            cmd = '-gen-disassembler',
            output = WEBASSEMBLY_TD_OUTDIR .. 'WebAssemblyGenDisassemblerTables.inc'
        },
        {
            WEBASSEMBLY_TD,
            cmd = '-gen-fast-isel',
            output = WEBASSEMBLY_TD_OUTDIR .. 'WebAssemblyGenFastISel.inc'
        },
        {
            WEBASSEMBLY_TD,
            cmd = '-gen-instr-info',
            output = WEBASSEMBLY_TD_OUTDIR .. 'WebAssemblyGenInstrInfo.inc'
        },
        {
            WEBASSEMBLY_TD,
            cmd = '-gen-emitter',
            output = WEBASSEMBLY_TD_OUTDIR .. 'WebAssemblyGenMCCodeEmitter.inc'
        },
        {
            WEBASSEMBLY_TD,
            cmd = '-gen-register-info',
            output = WEBASSEMBLY_TD_OUTDIR .. 'WebAssemblyGenRegisterInfo.inc'
        },
        {
            WEBASSEMBLY_TD,
            cmd = '-gen-subtarget',
            output = WEBASSEMBLY_TD_OUTDIR .. 'WebAssemblyGenSubtargetInfo.inc'
        })

local libtarget_webassembly = ninja.target('libtarget_webassembly')
    :type('static')
    :deps(llvm, tablegen_webassembly)
    :include_dir(LLVM_LIB_DIR .. 'Target/WebAssembly')
    :include_dir(WEBASSEMBLY_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/WebAssembly/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/WebAssembly/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/WebAssembly/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/WebAssembly/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/WebAssembly/TargetInfo/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/WebAssembly/Utils/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS XCore.td)

-- tablegen(LLVM XCoreGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM XCoreGenCallingConv.inc -gen-callingconv)
-- tablegen(LLVM XCoreGenDAGISel.inc -gen-dag-isel)
-- tablegen(LLVM XCoreGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM XCoreGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM XCoreGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM XCoreGenSubtargetInfo.inc -gen-subtarget)

local XCORE_TD = LLVM_LIB_DIR .. 'Target/XCore/XCore.td'
local XCORE_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_xcore = ninja.target('tablegen_xcore')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/XCore' },
            flags = { '--write-if-changed' },
        })
    :src({
            XCORE_TD,
            cmd = '-gen-asm-writer',
            output = XCORE_TD_OUTDIR .. 'XCoreGenAsmWriter.inc'
        },
        {
            XCORE_TD,
            cmd = '-gen-callingconv',
            output = XCORE_TD_OUTDIR .. 'XCoreGenCallingConv.inc'
        },
        {
            XCORE_TD,
            cmd = '-gen-dag-isel',
            output = XCORE_TD_OUTDIR .. 'XCoreGenDAGISel.inc'
        },
        {
            XCORE_TD,
            cmd = '-gen-disassembler',
            output = XCORE_TD_OUTDIR .. 'XCoreGenDisassemblerTables.inc'
        },
        {
            XCORE_TD,
            cmd = '-gen-instr-info',
            output = XCORE_TD_OUTDIR .. 'XCoreGenInstrInfo.inc'
        },
        {
            XCORE_TD,
            cmd = '-gen-register-info',
            output = XCORE_TD_OUTDIR .. 'XCoreGenRegisterInfo.inc'
        },
        {
            XCORE_TD,
            cmd = '-gen-subtarget',
            output = XCORE_TD_OUTDIR .. 'XCoreGenSubtargetInfo.inc'
        })

local libtarget_xcore = ninja.target('libtarget_xcore')
    :type('static')
    :deps(llvm, tablegen_xcore)
    :include_dir(LLVM_LIB_DIR .. 'Target/XCore')
    :include_dir(XCORE_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/XCore/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/XCore/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/XCore/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/XCore/TargetInfo/*.cpp')

-- set(LLVM_TARGET_DEFINITIONS Xtensa.td)

-- tablegen(LLVM XtensaGenAsmMatcher.inc -gen-asm-matcher)
-- tablegen(LLVM XtensaGenAsmWriter.inc -gen-asm-writer)
-- tablegen(LLVM XtensaGenDisassemblerTables.inc -gen-disassembler)
-- tablegen(LLVM XtensaGenInstrInfo.inc -gen-instr-info)
-- tablegen(LLVM XtensaGenMCCodeEmitter.inc -gen-emitter)
-- tablegen(LLVM XtensaGenRegisterInfo.inc -gen-register-info)
-- tablegen(LLVM XtensaGenSubtargetInfo.inc -gen-subtarget)

local XTENSA_TD = LLVM_LIB_DIR .. 'Target/Xtensa/Xtensa.td'
local XTENSA_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_xtensa = ninja.target('tablegen_xtensa')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen', LLVM_LIB_DIR .. 'Target/Xtensa' },
            flags = { '--write-if-changed' },
        })
    :src({
            XTENSA_TD,
            cmd = '-gen-asm-matcher',
            output = XTENSA_TD_OUTDIR .. 'XtensaGenAsmMatcher.inc'
        },
        {
            XTENSA_TD,
            cmd = '-gen-asm-writer',
            output = XTENSA_TD_OUTDIR .. 'XtensaGenAsmWriter.inc'
        },
        {
            XTENSA_TD,
            cmd = '-gen-disassembler',
            output = XTENSA_TD_OUTDIR .. 'XtensaGenDisassemblerTables.inc'
        },
        {
            XTENSA_TD,
            cmd = '-gen-instr-info',
            output = XTENSA_TD_OUTDIR .. 'XtensaGenInstrInfo.inc'
        },
        {
            XTENSA_TD,
            cmd = '-gen-emitter',
            output = XTENSA_TD_OUTDIR .. 'XtensaGenMCCodeEmitter.inc'
        },
        {
            XTENSA_TD,
            cmd = '-gen-register-info',
            output = XTENSA_TD_OUTDIR .. 'XtensaGenRegisterInfo.inc'
        },
        {
            XTENSA_TD,
            cmd = '-gen-subtarget',
            output = XTENSA_TD_OUTDIR .. 'XtensaGenSubtargetInfo.inc'
        })

local libtarget_xtensa = ninja.target('libtarget_xtensa')
    :type('static')
    :deps(llvm, tablegen_xtensa)
    :include_dir(LLVM_LIB_DIR .. 'Target/Xtensa')
    :include_dir(XTENSA_TD_OUTDIR)
    :src(LLVM_LIB_DIR .. 'Target/Xtensa/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Xtensa/AsmParser/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Xtensa/Disassembler/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Xtensa/MCTargetDesc/*.cpp')
    :src(LLVM_LIB_DIR .. 'Target/Xtensa/TargetInfo/*.cpp')

local libtarget = ninja.target('libtarget')
    :type('static')
    :deps(libtargetparser, libanalysis)
    :src(LLVM_DIR .. 'lib/Target/*.cpp')

local COFFOPTIONS_TD = LLVM_LIB_DIR .. 'ExecutionEngine/JITLink/COFFoptions.td'
local COFFOPTIONS_TD_OUTDIR = 'include/llvm/CodeGen/'

local tablegen_coffoptions = ninja.target('tablegen_coffoptions')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen' },
            flags = { '--write-if-changed' },
        })
    :src({
        COFFOPTIONS_TD,
        cmd = '-gen-opt-parser-defs',
        output = COFFOPTIONS_TD_OUTDIR .. 'COFFOptions.inc'
    })

local libee = ninja.target('libee')
    :type('static')
    :deps(libtarget, libtargetparser, tablegen_coffoptions)
    :include_dir(COFFOPTIONS_TD_OUTDIR)
    :src(LLVM_DIR .. 'lib/ExecutionEngine/*.cpp')
    :src(LLVM_DIR .. 'lib/ExecutionEngine/Interpreter/*.cpp')
    :src(LLVM_DIR .. 'lib/ExecutionEngine/JITLink/*.cpp')
    :src(LLVM_DIR .. 'lib/ExecutionEngine/MCJIT/*.cpp')
    :src(LLVM_DIR .. 'lib/ExecutionEngine/Orc/*.cpp')
    :src(LLVM_DIR .. 'lib/ExecutionEngine/Orc/Shared/*.cpp')
    :src(LLVM_DIR .. 'lib/ExecutionEngine/Orc/TargetProcess/*.cpp')
    :src(LLVM_DIR .. 'lib/ExecutionEngine/RuntimeDyld/*.cpp')
    :src(LLVM_DIR .. 'lib/ExecutionEngine/RuntimeDyld/Targets/*.cpp')

local libextensions = ninja.target('libextensions')
    :type('static')
    :deps(libsupport)
    :src(LLVM_DIR .. 'lib/Extensions/*.cpp')

local libfrontend_openmp = ninja.target('libfrontend_openmp')
    :type('static')
    :deps(libsupport)
    :include_dir(
        LLVM_INCLUDE_DIR .. 'llvm/Frontend',
        LLVM_INCLUDE_DIR .. 'llvm/Frontend/OpenMP'
    )
    :src(LLVM_DIR .. 'lib/Frontend/OpenMP/*.cpp')

local liblinker = ninja.target('liblinker')
    :type('static')
    :deps(libobject, libtransform_utils, libtargetparser)
    :src(LLVM_DIR .. 'lib/Linker/*.cpp')

local liblto = ninja.target('liblto')
    :type('static')
    :deps(liblinker, libmc)
    :src(LLVM_DIR .. 'lib/LTO/*.cpp')

local libobjcopy = ninja.target('libobjcopy')
    :type('static')
    :deps(libobject, libbinaryformat, libmc)
    :include_dir(LLVM_LIB_DIR .. 'ObjCopy')
    :src(LLVM_DIR .. 'lib/ObjCopy/*.cpp')
    :src(LLVM_DIR .. 'lib/ObjCopy/COFF/*.cpp')
    :src(LLVM_DIR .. 'lib/ObjCopy/XCOFF/*.cpp')
    :src(LLVM_DIR .. 'lib/ObjCopy/ELF/*.cpp')
    :src(LLVM_DIR .. 'lib/ObjCopy/MachO/*.cpp')
    :src(LLVM_DIR .. 'lib/ObjCopy/wasm/*.cpp')

local libobject_yaml = ninja.target('libobject_yaml')
    :type('static')
    :deps(libobject, libbinaryformat, libdebuginfo_codeview)
    :src(LLVM_DIR .. 'lib/ObjectYAML/*.cpp')

local liboption = ninja.target('liboption')
    :type('static')
    :deps(libsupport)
    :src(LLVM_DIR .. 'lib/Option/*.cpp')

local libpasses = ninja.target('libpasses')
    :type('static')
    :deps(libanalysis, libtransform_instrummentation, libtransform_scalar, libtransform_vectorize, libtransform_ipo,
        libtransform_coroutines, libtransform_cfguard, libtransform_objcarc, libtransform_aggressiveinstcombine,
        libtransform_instcombine)
    :src(LLVM_DIR .. 'lib/Passes/*.cpp')

local libgtest = ninja.target('libgtest')
    :type('static')
    :deps(libsupport)
    :include_dir(public { LLVM_ROOT .. 'third-party/unittest/googletest/include' })
    :include_dir({ LLVM_ROOT .. 'third-party/unittest/googletest' })
    :src(LLVM_ROOT .. 'third-party/unittest/googletest/src/gtest-all.cc')

local libgmock = ninja.target('libgmock')
    :type('static')
    :deps(libgtest)
    :include_dir(public { LLVM_ROOT .. 'third-party/unittest/googlemock/include' })
    :include_dir({ LLVM_ROOT .. 'third-party/unittest/googlemock' })
    :src(LLVM_ROOT .. 'third-party/unittest/googlemock/src/gmock-all.cc')

local libtesting = ninja.target('libtesting')
    :type('static')
    :deps(libgmock)
    :src(LLVM_DIR .. 'lib/Testing/Annotations/*.cpp')
    :src(LLVM_DIR .. 'lib/Testing/Support/*.cpp')

TOOLDRIVERS_DLLTOOL_TD = LLVM_DIR .. 'lib/ToolDrivers/llvm-dlltool/Options.td'
TOOLDRIVERS_DLLTOOL_TD_OUTDIR = 'include/llvm/ToolDrivers/llvm-dlltool/'

TOOLDRIVERS_LIB_TD = LLVM_DIR .. 'lib/ToolDrivers/llvm-lib/Options.td'
TOOLDRIVERS_LIB_TD_OUTDIR = 'include/llvm/ToolDrivers/llvm-lib/'

local tablegen_tooldrivers = ninja.target('tablegen_tooldrivers')
    :type('phony')
    :use(tablegen_tool, '.td',
        {
            include_dir = { 'include', LLVM_INCLUDE_DIR, LLVM_INCLUDE_DIR .. 'llvm/CodeGen' },
            flags = { '--write-if-changed' },
        })
    :src({
            TOOLDRIVERS_DLLTOOL_TD,
            cmd = '-gen-opt-parser-defs',
            output = TOOLDRIVERS_DLLTOOL_TD_OUTDIR .. 'Options.inc'
        },
        {
            TOOLDRIVERS_LIB_TD,
            cmd = '-gen-opt-parser-defs',
            output = TOOLDRIVERS_LIB_TD_OUTDIR .. 'Options.inc'
        })

local libtooldrivers = ninja.target('libtooldrivers')
    :type('static')
    :deps(libsupport, tablegen_tooldrivers)
    :src({ LLVM_DIR .. 'lib/ToolDrivers/llvm-dlltool/*.cpp', include_dir = TOOLDRIVERS_DLLTOOL_TD_OUTDIR })
    :src({ LLVM_DIR .. 'lib/ToolDrivers/llvm-lib/*.cpp', include_dir = TOOLDRIVERS_LIB_TD_OUTDIR })

local libwindowsdriver = ninja.target('libwindowsdriver')
    :type('static')
    :deps(libsupport)
    :src(LLVM_DIR .. 'lib/WindowsDriver/*.cpp')

local libwindowsmanifest = ninja.target('libwindowsmanifest')
    :type('static')
    :deps(libsupport)
    :src(LLVM_DIR .. 'lib/WindowsManifest/*.cpp')

local libxray = ninja.target('libxray')
    :type('static')
    :deps(libobject, libtargetparser)
    :src(LLVM_DIR .. 'lib/XRay/*.cpp')

local llc = ninja.target('llc')
    :type('binary')
    :deps(llvm)
    :lib('build/llvm.lib')
    :src(LLVM_DIR .. 'tools/llc/*.cpp')

local lli = ninja.target('lli')
    :type('binary')
    -- :deps(llvm, libee, liboption, libwindowsdriver)
    :deps(llvm)
    :lib('build/llvm.lib')
    :src(LLVM_DIR .. 'tools/lli/*.cpp')

-- ninja.build(lli)
lli:build()

-- llc:build()

-- ninja.build(llc)
