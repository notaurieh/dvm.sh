#!/bin/env bash

# TODO: Mac support and custom variables
export DVM_UPDATE_ENDPOINT="https://discordapp.com/api/v7/updates/%s?platform=linux"
export DVM_DL_ENDPOINT="https://%s.discordapp.net/apps/linux/%s/%s-%s.tar.gz"
export DVM_LOCAL=$HOME/.dvm

__containsElement() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# Partially stolen from https://gist.github.com/cjus/1047794
__jsonvalue() {
    # $1 = json
    # $2 = prop
    local IN
    local arrIN
    IN=$(echo $1 | sed 's/\\\\\//\//g' | sed 's/[{}]//g' | awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | sed 's/\"\:\"/\|/g' | sed 's/[\,]/ /g' | sed 's/\"//g' | grep --color=never -w $2)
    IFS=": "; arrIN=($IN); unset IFS
    echo "${arrIN[1]}"
}

_dvm_add_to_path() {
    if [ -L "$DVM_LOCAL/sym/dvm" ]; then
        rm $DVM_LOCAL/sym/dvm
    fi
    ln -s $(readlink -f $0) $DVM_LOCAL/sym/dvm
    export PATH=$PATH:$DVM_LOCAL/sym/$1
}

_dvm_usage() {
    echo "usage: dvm       <subcommand>"
    echo "subcommands:"
    echo "       default   <branch>"
    echo "       install   <branch>"
    echo "       update    <branch>"
    echo "       uninstall <branch>"
    echo "       list"
    # echo "todo:"
    # echo "       component apply     <branch> <name>"
    # echo "       component install   <name>"
    # echo "       component update    <name>"
    # echo "       component uninstall <name>"
}

_dvm_ensure_dir() {
    # $1 = dir
    if [ ! -d "$1" ]; then
        mkdir -p $DVM_LOCAL/$1
    fi
}

_dvm_ensure_dirs() {
    dirs=("sym" "branches" "components")
    for dir in "${dirs[@]}"; do
        _dvm_ensure_dir $dir
    done
}

_dvm_get_branch_specifier() {
    # $1 = branch
    if [ "$1" = "stable" ]; then
        echo ""
    elif [ "$1" = "canary" ]; then
        echo "Canary"
    elif [ "$1" = "ptb" ]; then
        echo "PTB"
    fi
}

_dvm_get_dlserver_suffix() {
    # $1 = branch
    if [ "$1" = "stable" ]; then
        echo ""
    else
        echo "-$1"
    fi
}

_dvm_default() {
    # $1 = branch
    local branch_specifier
    branch_specifier=$(_dvm_get_branch_specifier $1)
    _dvm_ensure_branch $1 $branch_specifier
    if [ -L "$DVM_LOCAL/sym/discord" ]; then
        rm "$DVM_LOCAL/sym/discord"
    fi
    ln -s $DVM_LOCAL/branches/$1/Discord$branch_specifier/Discord$branch_specifier $DVM_LOCAL/sym/discord
}

_dvm_get_version() {
    # $1 = branch
    local update_url
    local json
    update_url=$(printf $DVM_UPDATE_ENDPOINT $1)
    json=$(curl -o- -XGET -s -H "DVM" $update_url)
    if [[ $json == *"404"* ]]; then
        echo "Branch $1 not found: Discord returned 404"
        exit 1
    fi
    __jsonvalue "$json" name
}

_dvm_install_version() {
    # $1 = branch
    # $2 = version
    local dlserver_suffix
    local dlserver_suffix_
    local DL_PATH
    local tempfile
    dlserver_suffix_=$(_dvm_get_dlserver_suffix $1)
    dlserver_suffix="dl$dlserver_suffix_"
    DL_PATH=$(printf "$DVM_DL_ENDPOINT" $dlserver_suffix $2 "discord$dlserver_suffix_" $2)
    echo "Downloading from $DL_PATH"
    tempfile=$(mktemp --suffix .tar.gz)
    curl -o $tempfile -XGET --progress-bar -H "DVM" $DL_PATH
    mkdir $DVM_LOCAL/branches/$1/
    tar -xzf $tempfile -C $DVM_LOCAL/branches/$1
    echo $version > $DVM_LOCAL/branches/$1/Discord$(_dvm_get_branch_specifier $1)/.version
}

_dvm_install() {
    # $1 = branch
    local version
    local is_installed
    local branch_specifier
    branch_specifier=$(_dvm_get_branch_specifier $1)
    is_installed=$(__dvm_ensure_branch $1 $branch_specifier)
    if [ -z "$is_installed" ]; then
        echo "Branch $1 is already installed. Try dvm update <branch>"
        exit 1
    fi
    version=$(_dvm_get_version $1)
    echo "Newest version $version"
    _dvm_install_version $1 $version
}

_dvm_uninstall() {
    # $1 = branch
    # TODO: Unlink if default
    rm -rf $DVM_LOCAL/branches/$1
}

_dvm_version_greater() {
    # $1 = old_version (array of numbers)
    # $2 = new_version (array of numbers)
    # TODO: Clean this up, I'm sure there's a better way
    local OLD_MAJOR
    local OLD_MINOR
    local OLD_PATCH
    local NEW_MAJOR
    local NEW_MINOR
    local NEW_PATCH
    OLD_MAJOR=${old_version[0]}
    OLD_MINOR=${old_version[1]}
    OLD_PATCH=${old_version[2]}
    NEW_MAJOR=${new_version[0]}
    NEW_MINOR=${new_version[1]}
    NEW_PATCH=${new_version[2]}
    if [ "$NEW_MAJOR" -gt "$OLD_MAJOR" ]; then
        echo "t"
    fi
    if [ "$NEW_MINOR" -gt "$OLD_MINOR" ]; then
        echo "t"
    fi
    if [ "$NEW_PATCH" -gt "$OLD_PATCH" ]; then
        echo "t"
    fi
}

__dvm_ensure_branch() {
    # $1 = branch
    # $2 = branch specifier
    if [ ! -d "$DVM_LOCAL/branches/$1" ]; then
        echo 1
    elif [ ! -f "$DVM_LOCAL/branches/$1/Discord$2/.version" ]; then
        echo 2
    fi
}

_dvm_ensure_branch() {
    # $1 = branch
    # $2 = branch specifier
    case $(__dvm_ensure_branch $1 $2) in
        "1")
            echo "Branch $1 not found. Maybe try dvm install <branch>"
            exit 1
            ;;
        "2")
            echo "Branch $1 found but missing .version file. Is it not managed by DVM?"
            exit 1
            ;;
    esac
}

_dvm_update() {
    # $1 = branch
    local branch_specifier
    branch_specifier=$(_dvm_get_branch_specifier $1)
    _dvm_ensure_branch $1 $branch_specifier
    local outdated
    local new_version_
    old_version=$(cat $DVM_LOCAL/branches/$1/Discord$branch_specifier/.version)
    new_version_=$(_dvm_get_version $1)
    IFS="."
    old_version=($old_version)
    new_version=($new_version_)
    unset IFS
    # TODO: Clean up
    outdated=$(_dvm_version_greater)
    if [ -z "$outdated" ]; then
        echo "Already up to date."
        exit 0
    fi
    _dvm_uninstall $1
    _dvm_install_version $1 $new_version_
}

_dvm_run() {
    # $1 = branch
    local branch_specifier
    branch_specifier=$(_dvm_get_branch_specifier $1)
    _dvm_ensure_branch $1 $branch_specifier
    $DVM_LOCAL/branches/$1/Discord$branch_specifier/Discord$branch_specifier
}

_dvm_get_answer() {
    read -p "Are you sure you want to do this? " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "t"
    fi
    unset REPLY
}

_dvm_clean() {
    # $1 = branch
    local branch_specifier
    branch_specifier=$(_dvm_get_branch_specifier $1)
    _dvm_ensure_branch $1 $branch_specifier
    branch_specifier=$(echo $branch_specifier | tr '[:upper:]' '[:lower:]')
    echo "This utility will clear all Discord cache for $1 branch."
    echo "Cache includes your password and most 3rd party tools you've installed!"
    if [ ! -z "$(_dvm_get_answer)" ]; then
        echo
        echo "Cleaning ~/.config/discord$branch_specifier"
        rm -rf $HOME/.config/discord$branch_specifier
    fi
}

_dvm_get_shell() {
    # TODO: Improve this
    if [[ $SHELL = *zsh* ]]; then
        echo "zsh"
    elif [[ $SHELL = *bash* ]]; then
        echo "bash"
    fi
}

__dvm_update_zsh_env() {
    echo >> $HOME/.zshenv
    echo "path=($DVM_LOCAL/sym \$path)" >> $HOME/.zshenv
}

__dvm_update_bash_env() {
    echo >> $HOME/.bash_profile
    echo "export PATH=\$PATH:$DVM_LOCAL/sym" >> $HOME/.bash_profile
}

_dvm_update_path() {
    echo "This utility will append PATH changes to your shell configuration."
    if [ "$(_dvm_get_answer)" = "t" ]; then
        echo
        case "$(_dvm_get_shell)" in
            "zsh")
                __dvm_update_zsh_env
                ;;
            "bash")
                __dvm_update_bash_env
                ;;
            *)
                echo "At the current time, this utility only supports ZSH and Bash"
                exit 1
        esac
        _dvm_add_to_path
    fi
}

_dvm_list() {
    local stable_version
    local ptb_version
    local canary_version
    stable_version=$(_dvm_get_version stable)
    ptb_version=$(_dvm_get_version ptb)
    canary_version=$(_dvm_get_version canary)
    printf "stable - %s\n" $stable_version
    printf "ptb    - %s\n" $ptb_version
    printf "canary - %s\n" $canary_version
}

_dvm_desktop() {
    local link
    local desktop
    local branch_specifier
    link=$(readlink $DVM_LOCAL/sym/dvm)
    link=$(dirname $link)
    link=$(printf "%s/%s" $link "DiscordDVM.desktop")
    branch_specifier=$(_dvm_get_branch_specifier $1)
    desktop=$(cat $link | sed 's@{dvm_local}@'$DVM_LOCAL'@g')
    desktop=$(echo "$desktop" | sed 's/{branch}/'$1'/g')
    desktop=$(echo "$desktop" | sed 's/{branch_specifier}/'$branch_specifier'/g')
    echo "$desktop"
}

_dvm_ensure_args() {
    # $1 = args num
    # $2 = required args num
    if [ "$1" -lt "$2" ]; then
        echo "Invalid number of arguments passed."
        _dvm_usage
        exit 1
    fi
}

dvm() {
    _dvm_ensure_args $# 1
    arglessSubcommands=("update_path", "list")
    _dvm_ensure_dirs
    __containsElement "$1" "${arglessSubcommands[@]}"
    if [ "$?" -gt "1" ]; then
        _dvm_ensure_args $# 2
    fi
    if [ ! -n "$(type -t _dvm_$1)" ]; then
        echo "$1: no such action."
        _dvm_usage
        exit 1
    fi
    _dvm_$1 ${@:2}
}

dvm $@

# vim:shiftwidth=4
