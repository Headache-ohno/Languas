#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$PROJECT_ROOT"

BUILD_TARGET=host
HOST_ARCH=native
APPLICATION=all
DRY_RUN=0
LIST_ONLY=0
CLEAN_ONLY=0
SANITIZE=0

CC_BIN=${CC:-clang}
LD_BIN=${LD:-ld.lld}
OBJCOPY_BIN=${OBJCOPY:-llvm-objcopy}

usage() {
    echo "usage: $0 [application|all] [--target host|arm|all] [--arch native|x86|x64]"
    echo "       $0 --list"
    echo "       $0 --clean"
}

die() {
    echo "error: $*" >&2
    exit 1
}

run() {
    printf '+'
    for argument do
        printf ' %s' "$argument"
    done
    printf '\n'
    if [ "$DRY_RUN" -eq 0 ]; then
        "$@"
    fi
}

read_field() {
    manifest=$1
    field=$2
    sed -n "s/^${field}:[[:space:]]*//p" "$manifest" | sed -n '1p'
}

find_manifest() {
    wanted=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    for candidate in modules/*/*.lgm; do
        [ -f "$candidate" ] || continue
        [ "$(sed -n '1p' "$candidate")" = LGM1 ] || die "$candidate: expected LGM1 header"
        found_name=$(read_field "$candidate" Name)
        case "$found_name" in
            ''|*[!A-Za-z0-9_]*) die "$candidate: Name must be an ASCII identifier" ;;
        esac
        case "$found_name" in
            [A-Za-z]*) ;;
            *) die "$candidate: Name must begin with an ASCII letter" ;;
        esac
        [ -n "$(read_field "$candidate" Sources)" ] || die "$candidate: Sources is required"
        found=$(printf '%s' "$found_name" | tr '[:upper:]' '[:lower:]')
        if [ "$found" = "$wanted" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

RESOLVED=
VISITING=

resolve_module() {
    module_name=$1
    case " $RESOLVED " in *" $module_name "*) return 0 ;; esac
    case " $VISITING " in *" $module_name "*) die "module dependency cycle at $module_name" ;; esac

    if ! module_manifest=$(find_manifest "$module_name"); then
        die "unknown module: $module_name"
    fi
    canonical_name=$(read_field "$module_manifest" Name)
    VISITING="$VISITING $canonical_name"
    dependencies=$(read_field "$module_manifest" Depends | tr ',' ' ')
    for dependency in $dependencies; do
        resolve_module "$dependency"
    done
    canonical_name=$(read_field "$(find_manifest "$1")" Name)
    VISITING=$(printf '%s' "$VISITING" | sed "s/ $canonical_name$//")
    RESOLVED="$RESOLVED $canonical_name"
}

resolve_application() {
    if ! application_manifest=$(find_manifest "$1"); then
        die "unknown application: $1"
    fi
    application_profile=$(read_field "$application_manifest" Profile)
    [ -n "$application_profile" ] || die "$1 is a library module, not an application"
    application_name=$(read_field "$application_manifest" Name)
    RESOLVED=
    VISITING=
    resolve_module "$application_name"
}

arm_compile() {
    source_file=$1
    object_file=$2
    profile=$3

    set -- "$CC_BIN" -target arm-none-eabi -mcpu=cortex-m0 -mthumb \
        -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
        -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-exceptions \
        -Os -Wall -Wextra -Wpedantic -Werror -DLG_TARGET_ARMV6M=1 \
        -I core "-DCONFIG_PROFILE=$profile"
    for selected_module in $RESOLVED; do
        selected_manifest=$(find_manifest "$selected_module")
        set -- "$@" -I "$(dirname -- "$selected_manifest")"
        definitions=$(read_field "$selected_manifest" Defines | tr ',' ' ')
        for definition in $definitions; do
            set -- "$@" "-D$definition"
        done
    done
    set -- "$@" -c "$source_file" -o "$object_file"
    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$(dirname -- "$object_file")"
    fi
    run "$@"
}

build_native_tools() {
    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p build_arm/tools
    fi
    run "$CC_BIN" -Wall -Wextra -Wpedantic -Werror -Os tools/rom_packer.c -o build_arm/tools/rom_packer
    run "$CC_BIN" -Wall -Wextra -Wpedantic -Werror -Os tools/rom_inspect.c -o build_arm/tools/rom_inspect
}

build_arm_application() {
    resolve_application "$1"
    lower_name=$(printf '%s' "$application_name" | tr '[:upper:]' '[:lower:]')
    build_directory="build_arm/$lower_name"
    boot_objects=
    app_objects=

    echo
    echo "== ARM $application_name:$RESOLVED =="
    for source_file in bootex/startup_bootex.c bootex/bootex.c; do
        object_file="$build_directory/obj/${source_file%.c}.o"
        arm_compile "$source_file" "$object_file" "$application_profile"
        boot_objects="$boot_objects $object_file"
    done

    for source_file in core/languas_header.c core/languas_core.c targets/armv6m/platform_armv6m.c; do
        object_file="$build_directory/obj/${source_file%.c}.o"
        arm_compile "$source_file" "$object_file" "$application_profile"
        app_objects="$app_objects $object_file"
    done
    for selected_module in $RESOLVED; do
        selected_manifest=$(find_manifest "$selected_module")
        selected_directory=$(dirname -- "$selected_manifest")
        source_names=$(read_field "$selected_manifest" Sources | tr ',' ' ')
        for source_name in $source_names; do
            case "$source_name" in
                /*|../*|*/../*|*/..) die "$selected_manifest: source escapes its module directory" ;;
            esac
            source_file="$selected_directory/$source_name"
            [ -f "$source_file" ] || die "$selected_manifest: missing source $source_name"
            object_file="$build_directory/obj/${source_file%.c}.o"
            arm_compile "$source_file" "$object_file" "$application_profile"
            app_objects="$app_objects $object_file"
        done
    done

    set -- "$LD_BIN" -nostdlib --gc-sections -T bootex/bootex.ld
    for object_file in $boot_objects; do set -- "$@" "$object_file"; done
    set -- "$@" -o "$build_directory/bootex.elf"
    run "$@"

    set -- "$LD_BIN" -nostdlib --gc-sections -T targets/armv6m/languas.ld
    for object_file in $app_objects; do set -- "$@" "$object_file"; done
    set -- "$@" -o "$build_directory/languas.elf"
    run "$@"

    run "$OBJCOPY_BIN" -O binary "$build_directory/bootex.elf" "$build_directory/bootex.bin"
    run "$OBJCOPY_BIN" -O binary "$build_directory/languas.elf" "$build_directory/languas.bin"
    if [ "$DRY_RUN" -eq 0 ]; then mkdir -p output; fi
    temporary_rom="output/languas_$lower_name.rom.tmp"
    final_rom="output/languas_$lower_name.rom"
    run build_arm/tools/rom_packer "$build_directory/bootex.bin" \
        "$build_directory/languas.bin" "$temporary_rom"
    run build_arm/tools/rom_inspect verify "$temporary_rom"
    run mv -f "$temporary_rom" "$final_rom"
}

build_host_application() {
    resolve_application "$1"
    lower_name=$(printf '%s' "$application_name" | tr '[:upper:]' '[:lower:]')
    architecture_suffix=

    echo
    echo "== HOST $application_name:$RESOLVED =="
    set -- "$CC_BIN" -Wall -Wextra -Wpedantic -Werror -Os -I core \
        "-DCONFIG_PROFILE=$application_profile"
    if [ "$SANITIZE" -eq 1 ]; then
        set -- "$@" -g -fno-omit-frame-pointer -fsanitize=address,undefined
    fi
    case "$HOST_ARCH" in
        native) ;;
        x86) set -- "$@" -m32; architecture_suffix=_x86 ;;
        x64) set -- "$@" -m64; architecture_suffix=_x64 ;;
        *) die "unsupported host architecture: $HOST_ARCH" ;;
    esac

    for selected_module in $RESOLVED; do
        selected_manifest=$(find_manifest "$selected_module")
        selected_directory=$(dirname -- "$selected_manifest")
        set -- "$@" -I "$selected_directory"
        definitions=$(read_field "$selected_manifest" Defines | tr ',' ' ')
        for definition in $definitions; do set -- "$@" "-D$definition"; done
    done

    set -- "$@" core/languas_header.c core/languas_core.c
    for selected_module in $RESOLVED; do
        selected_manifest=$(find_manifest "$selected_module")
        selected_directory=$(dirname -- "$selected_manifest")
        source_names=$(read_field "$selected_manifest" Sources | tr ',' ' ')
        for source_name in $source_names; do
            case "$source_name" in
                /*|../*|*/../*|*/..) die "$selected_manifest: source escapes its module directory" ;;
            esac
            [ -f "$selected_directory/$source_name" ] ||
                die "$selected_manifest: missing source $source_name"
            set -- "$@" "$selected_directory/$source_name"
        done
    done
    set -- "$@" targets/host/platform_host.c targets/host/main_host.c
    if [ "$DRY_RUN" -eq 0 ]; then mkdir -p output; fi
    set -- "$@" -o "output/languas_${lower_name}${architecture_suffix}"
    run "$@"
}

build_selected_applications() {
    selected_target=$1
    if [ "$APPLICATION" = all ]; then
        for application_candidate in modules/*/*.lgm; do
            [ -n "$(read_field "$application_candidate" Profile)" ] || continue
            candidate_name=$(read_field "$application_candidate" Name)
            if [ "$selected_target" = arm ]; then
                build_arm_application "$candidate_name"
            else
                build_host_application "$candidate_name"
            fi
        done
    elif [ "$selected_target" = arm ]; then
        build_arm_application "$APPLICATION"
    else
        build_host_application "$APPLICATION"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target) [ "$#" -ge 2 ] || die '--target needs a value'; BUILD_TARGET=$2; shift 2 ;;
        --arch) [ "$#" -ge 2 ] || die '--arch needs a value'; HOST_ARCH=$2; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --sanitize) SANITIZE=1; shift ;;
        --list) LIST_ONLY=1; shift ;;
        --clean) CLEAN_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *) APPLICATION=$1; shift ;;
    esac
done

case "$BUILD_TARGET" in host|arm|all) ;; *) die "unsupported target: $BUILD_TARGET" ;; esac
case "$HOST_ARCH" in native|x86|x64) ;; *) die "unsupported host architecture: $HOST_ARCH" ;; esac

if [ "$LIST_ONLY" -eq 1 ]; then
    for manifest in modules/*/*.lgm; do
        module_name=$(read_field "$manifest" Name)
        module_profile=$(read_field "$manifest" Profile)
        module_dependencies=$(read_field "$manifest" Depends)
        [ -n "$module_profile" ] || module_profile=library
        [ -n "$module_dependencies" ] || module_dependencies=none
        printf '%-12s %-10s depends: %s\n' "$module_name" "$module_profile" "$module_dependencies"
    done
    exit 0
fi

if [ "$CLEAN_ONLY" -eq 1 ]; then
    echo "remove $PROJECT_ROOT/build_arm"
    echo "remove $PROJECT_ROOT/output"
    rm -rf -- "$PROJECT_ROOT/build_arm" "$PROJECT_ROOT/output"
    exit 0
fi

if [ "$BUILD_TARGET" = arm ] || [ "$BUILD_TARGET" = all ]; then
    build_native_tools
    build_selected_applications arm
fi
if [ "$BUILD_TARGET" = host ] || [ "$BUILD_TARGET" = all ]; then
    build_selected_applications host
fi
