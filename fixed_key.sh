#!/bin/bash
function fixkey() {
        if [ -z $1 ]
        then
                echo -e "\t\e[1;30mNo key supplied, so no fix\e[0m" && return
        fi
        echo -e "Fixing key \t\e[1;36m$1\e[0m..."

        # Права (на всякий)
        chmod 600 "$1"
        # Убрать UTF-8 BOM (если есть)
        sed -i '1s/^\xEF\xBB\xBF//' "$1"
        # Убрать CR на концах строк (если вдруг затесались)
        perl -pi -e 's/\r$//' "$1"
        # Убрать пробелы/табы в конце строк (в т.ч. после BEGIN/END)
        perl -pi -e 's/[ \t]+$//' "$1"
        # На всякий: гарантировать перевод строки в конце файла
        tail -c1 "$KEY" | read -r _ || echo >> "$1"

        echo -e "\t\e[1;32mKey $1 FIXED\e[0m"
}
export PWD="$(pwd)"
for file in $(ls -1 $PWD | grep 'key');
do
        export KEYPATH="$PWD/$file"
        ssh-keygen -l -f "$KEYPATH" &> /dev/null
        if [[ "$(echo $?)" == 0 ]];
        then
                echo -e "\e[1;33mKey $KEYPATH valid\e[0m"
        else
                echo -e "\e[1;31mKey $KEYPATH is INVALID\e[0m"
                fixkey $KEYPATH
        fi
        unset KEYPATH
done
unset PWD
