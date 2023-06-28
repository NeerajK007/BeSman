#!/bin/bash

function __bes_create
{
   
    # bes create --playbook cve vuln name ext  
    local type=$1 #stores the type of the input - playbook/environment
    local return_val 
    
    # Checks whether the $type is playbook or not
    if [[ $type == "--playbook" || $type == "-P" ]]; then
    
        # checks whether the user github id has been populated or not under $BESMAN_USER_NAMESPACE 
        __besman_check_github_id || return 1
        # checks whether the user has already logged in or not to gh tool
        __besman_gh_auth_status "$BESMAN_USER_NAMESPACE"
        return_val=$?
        # if return_val == 0 then the user is already logged in
        if [[ $return_val == "0" ]]; then
    
            __besman_echo_white "Already logged in as $BESMAN_USER_NAMESPACE"

        # if return_val !=0 then user is not logged in
        else

            __besman_echo_white "authenticating.."
            __besman_gh_auth || return 1 
        
        fi
        
        __besman_echo_white "forking"
        __besman_gh_fork "$BESMAN_NAMESPACE" "$BESMAN_PLAYBOOK_REPO" 
        
        [[ "$?" != "0" ]] && return 1        
        
        if [[ ! -d $HOME/$BESMAN_PLAYBOOK_REPO ]]; then
            __besman_echo_white "cloning"  
            __besman_gh_clone "$BESMAN_USER_NAMESPACE" "$BESMAN_PLAYBOOK_REPO" "$HOME/$BESMAN_PLAYBOOK_REPO"
            [[ "$?" != "0" ]] && return 1
        
        fi
        
        local flag=$2
        local purpose=$3
        local vuln=$4
        local env=$5
        local ext=$6
        
        [[ -z $ext ]] && ext="md"
        
        __besman_create_playbook "$purpose" "$vuln" "$env" "$ext" 

        

        unset vuln env ext target_path return_val purpose
    else
        # bes create -env fastjson-RT-env 
        # $1 would be the type - env/playbook
        local environment_name overwrite template_type env_file version ossp env_file_name
        environment_name=$2
        version=$3
        template_type=$4
        [[ -z $version ]] && version="0.0.1"
        ossp=$(echo "$environment_name" | cut -d "-" -f 1)
        env_file_name="besman-$environment_name.sh"
        __besman_set_variables
        env_file_path=$BESMAN_LOCAL_ENV_DIR/$ossp/$version/$env_file_name
        mkdir -p "$BESMAN_LOCAL_ENV_DIR/$ossp/$version"
        if [[ -f "$env_file_path" ]]; then
            __besman_echo_yellow "File exists with the same name under $env_file_path"
            read -rp "Do you wish to overwrite (y/n)?: " overwrite
            if [[ ( "$overwrite" == "" ) || ( "$overwrite" == "y" ) || ( "$overwrite" == "Y" ) ]]; then
                rm "$env_file_path"
            else
                __besman_echo_yellow "Exiting..."
                return 1
            fi
        fi
        
        if [[ ( -n "$template_type" ) && ( "$template_type" == "basic" ) ]]; then

            __besman_create_env_basic "$env_file_path" || return 1
        elif [[ -z "$template_type" ]]; then
            __besman_create_env_with_config "$env_file_path" 
            __besman_create_env_config "$environment_name" "$version"

        fi

    fi
    __besman_update_env_dir_list "$environment_name" "$version"
    code "$env_file_path" 
}

function __besman_set_variables()
{
    local path
    __bes_set "BESMAN_LOCAL_ENV" "True"
    [[ -n $BESMAN_LOCAL_ENV_DIR ]] && return 0
    while [[ ( -z $path ) || ( ! -d $path )  ]] 
    do
        read -rp "Enter the complete path to your local environment directory: " path
    done
    __bes_set "BESMAN_LOCAL_ENV_DIR" "$path"

}

function __besman_create_env_config()
{
    local environment_name config_file ossp_name env_type config_file_path version overwrite
    environment_name=$1
    version=$2
    ossp_name=$(echo "$environment_name" | cut -d "-" -f 1)
    env_type=$(echo "$environment_name" | cut -d "-" -f 2)
    config_file="besman-$ossp_name-$env_type-env-config.yaml"
    config_file_path=$BESMAN_LOCAL_ENV_DIR/$ossp/$version/$config_file
    if [[ -f $config_file_path ]]; then
        __besman_echo_yellow "Config file $config_file exists under $BESMAN_LOCAL_ENV_DIR/$ossp/$version"
        read -rp " Do you wish to replace?(y/n): " overwrite
        if [[ ( "$overwrite" == "" ) || ( "$overwrite" == "y" ) || ( "$overwrite" == "Y" ) ]]; then
            rm "$config_file_path"
        else
            return 
        fi
    fi
    [[ ! -f $config_file_path ]] && touch "$config_file_path" && __besman_echo_yellow "Creating new config file $config_file_path"
    cat <<EOF > "$config_file_path"
---
BESMAN_ORG: Be-Secure
BESMAN_OSSP: $ossp_name
BESMAN_OSSP_CLONE_PATH: \$HOME/\$BESMAN_OSSP
BESMAN_ANSIBLE_ROLES_PATH: \$BESMAN_DIR/tmp/\$BESMAN_OSSP/roles
BESMAN_ANSIBLE_ROLES: 
BESMAN_OSS_TRIGGER_PLAYBOOK_PATH: \$BESMAN_DIR/tmp/\$BESMAN_OSSP
BESMAN_OSS_TRIGGER_PLAYBOOK: besman-\$BESMAN_OSSP-$env_type-trigger-playbook.yaml
BESMAN_DISPLAY_SKIPPED_ANSIBLE_HOSTS: false
# Please add other variables as well as ansible variables here
EOF
    code "$config_file_path" 
}

function __besman_create_env_with_config()
{
    local env_file_path
    env_file_path=$1

    cat <<EOF > "$env_file_path"
#!/bin/bash

function __besman_install_$environment_name
{
    
    __besman_check_for_gh || return 1
    __besman_check_github_id || return 1
    __besman_check_for_ansible || return 1
    __besman_update_requirements_file
    __besman_ansible_galaxy_install_roles_from_requirements
    __besman_check_for_trigger_playbook "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK"
    [[ "\$?" -eq 1 ]] && __besman_create_ansible_playbook
    __besman_run_ansible_playbook_extra_vars "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK" "bes_command=install role_path=\$BESMAN_ANSIBLE_ROLES_PATH" || return 1
    if [[ -d \$BESMAN_OSSP_CLONE_PATH ]]; then
        __besman_echo_white "The clone path already contains dir names \$BESMAN_OSSP"
    else
        __besman_gh_clone "\$BESMAN_ORG" "\$BESMAN_OSSP" "\$BESMAN_OSSP_CLONE_PATH"
    fi
    # Please add the rest of the code here for installation
}

function __besman_uninstall_$environment_name
{
    __besman_check_for_trigger_playbook "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK"
    [[ "\$?" -eq 1 ]] && __besman_create_ansible_playbook
    __besman_run_ansible_playbook_extra_vars "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK" "bes_command=remove role_path=\$BESMAN_ANSIBLE_ROLES_PATH" || return 1
    if [[ -d \$BESMAN_OSSP_CLONE_PATH ]]; then
        __besman_echo_white "Removing \$BESMAN_OSSP_CLONE_PATH..."
        rm -rf "\$BESMAN_OSSP_CLONE_PATH"
    else
        __besman_echo_yellow "Could not find dir \$BESMAN_OSSP_CLONE_PATH"
    fi
    # Please add the rest of the code here for uninstallation

}

function __besman_update_$environment_name
{
    __besman_check_for_trigger_playbook "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK"
    [[ "\$?" -eq 1 ]] && __besman_create_ansible_playbook
    __besman_run_ansible_playbook_extra_vars "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK" "bes_command=update role_path=\$BESMAN_ANSIBLE_ROLES_PATH" || return 1
    # Please add the rest of the code here for update

}

function __besman_validate_$environment_name
{
    __besman_check_for_trigger_playbook "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK"
    [[ "\$?" -eq 1 ]] && __besman_create_ansible_playbook
    __besman_run_ansible_playbook_extra_vars "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK" "bes_command=validate role_path=\$BESMAN_ANSIBLE_ROLES_PATH" || return 1
    # Please add the rest of the code here for validate

}

function __besman_reset_$environment_name
{
    __besman_check_for_trigger_playbook "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK"
    [[ "\$?" -eq 1 ]] && __besman_create_ansible_playbook
    __besman_run_ansible_playbook_extra_vars "\$BESMAN_OSS_TRIGGER_PLAYBOOK_PATH/\$BESMAN_OSS_TRIGGER_PLAYBOOK" "bes_command=reset role_path=\$BESMAN_ANSIBLE_ROLES_PATH" || return 1
    # Please add the rest of the code here for reset

}
EOF
    __besman_echo_white "Created env file $environment_name under $BESMAN_DIR/envs"

}

function __besman_create_env_basic
{
    local env_file_path
    env_file_path=$1
    [[ -f $env_file_path ]] && __besman_echo_red "Environment file exists" && return 1
    touch "$env_file_path"
    cat <<EOF > "$env_file_path"
#!/bin/bash

function __besman_install_$environment_name
{

}

function __besman_uninstall_$environment_name
{
    
}

function __besman_update_$environment_name
{
    
}

function __besman_validate_$environment_name
{
    
}

function __besman_reset_$environment_name
{
    
}
EOF
__besman_echo_white "Creating env file.."
}

function __besman_update_env_dir_list()
{
    local environment_name version
    environment_name=$1
    version=$2

    if grep -qw "Be-Secure/besecure-ce-env-repo/$environment_name,$version" "$BESMAN_LOCAL_ENV_DIR/list.txt"
    then
        return 1
    else
        __besman_echo_white "Updating local list"
        echo "Be-Secure/besecure-ce-env-repo/$environment_name,$version" >> "$BESMAN_LOCAL_ENV_DIR/list.txt"
    fi
    
}


function __besman_create_playbook
{
    local args=("${@}")
    # checks whether any parameters are empty and if empty assign it as untitled.
    for (( i=0;i<${#};i++ ))
    do
        if [[ -z ${args[$i]}  ]]; then
            args[$i]="untitled"

        fi
    
    done
    
    local purpose=${args[0]} # CVE/assessment etc..
    local vuln=${args[1]}
    local env=${args[2]}
    local ext=${args[3]}
    # [[ -z $ext ]] && ext="md"
    local target_path=$HOME/$BESMAN_PLAYBOOK_REPO
    
    touch $target_path/besman-$purpose-$vuln-$env-playbook.$ext
    
    if [[ "$?" == "0" ]]; then
    
    __besman_echo_green "Playbook created successfully"
    
    else
    
    __besman_echo_red "Could not create playbook"
    
    fi
    
    # opens the created playbook in a jupyter notebook/vscode
    __besman_open_file $target_path
    
    unset args vuln env ext purpose
}   

