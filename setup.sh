#!/bin/bash
set -eo pipefail

CWD=$(dirname ${BASH_SOURCE})
declare destroy
declare apply
declare plan
declare init
declare validate

check_dependencies() {
    declare -r deps=(terraform aws wget)
    declare -r install_docs=(
        'https://github.com/hashicorp/terraform/releases/latest'
        'https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html'
        'https://www.gnu.org/software/wget/'
    )

    for ((i = 0, f = 0; i < ${#deps[@]}; i++)); do
        if ! command -v ${deps[$i]} &>/dev/null; then
            ((++f)) && echo "'${deps[$i]}' command is not found. Please refer to ${install_docs[$i]} for proper installation."
        fi
    done

    if [[ $f -ne 0 ]]; then
        exit 127
    fi
}

read_var_file() {
    tfvarfile=$1
    local dirtyfile=0
    for line in ${tfvarfile[@]}
    do
        [[ $line = \#* ]] && continue
        key=`echo $line | awk -F'=' '{print $1}'`
        val=`echo $line | awk -F'=' '{print $2}'`
        if [ -z $val ];then
            echo "Value for key:$key cannot be empty $val"
            dirtyfile=1
        fi        
    done 
    return $dirtyfile
}

check_vpc_vars() {
    if [ -e ./vpc.tfvars ];then
        tfvarfile=$(cat ./vpc/vpc.tfvars)
        read_var_file $tfvarfile
        dirtyfile=$0
        if [ "$dirtyfile" = 1 ];then
            echo "Please fix vpc/vpc.tfvars to proceed!!" 
            exit 1
        fi
        printf "===vpc varfile===\n"
        echo $tfvarfile
    else
        echo "Please add file vpc.tfvars"
        exit 1
    fi
}

check_svc_vars() {
    if  [ -e ./setup.tfvars ]; then 
        tfvarfile=$(cat ./setup.tfvars)
        read_var_file $tfvarfile
        dirtyfile=$0
        if [ "$dirtyfile" = true ];then
            echo "Please fix setup.tfvars to proceed!!" 
            exit 1
        fi
        printf "===svc varfile===\n"
        echo "${tfvarfile}"
    else
        echo "Please add file setup.tfvars"
        exit 1
    fi
}

read_input() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--init)
                init="true"
                shift 1
                ;;
            -d|--destroy)
                destroy="true"
                shift 1
                ;;
            -p|--plan)
                plan="true"
                shift 1
                ;;
            -a|--apply)
                apply="true"
                shift 1
                ;;
            -v|--validate)
                validate="true"
                shift 1
                ;;
        esac
    done
}

run_tf_cmd() {
    tfplanoutputfile=$1
    tfvarfile=$2
    local output
    if [ "$destroy" = true ];then
        echo "===Runnning uninstall script==="
        terraform destroy  -auto-approve -var-file=$tfvarfile $tfplanoutputfile
    elif [ "$validate" = true ];then
        echo "===Runnning terraform validate script only==="
        terraform validate
    elif [ "$init" = true ];then
        echo "===Runnning terraform init script only==="
        terraform init -var-file=$tfvarfile
    elif [ "$plan" = true ];then
        echo "===Runnning terraform plan script only==="
        terraform plan -var-file=$tfvarfile
    elif [ "$apply" = true ];then
        echo "===Runnning terraform apply script only==="
        terraform refresh
        terraform apply  -auto-approve -var-file=$tfvarfile
    else
        echo "Runnning install script"
        terraform init -var-file=$tfvarfile
        # # plan and apply
        terraform plan -var-file=$tfvarfile -out $tfplanoutputfile
        terraform apply -auto-approve -var-file=$tfvarfile $tfplanoutputfile
    fi
}

get_tf_output() {
    output_var=$1
    output=$(terraform output $output_var)
    return $output
}

get_consumer_svc_pkg() {
    printf "===Getting screwdriver consumer-service package===\n"
    mkdir -p aws-consumer-service
    cd aws-consumer-service
    wget -q -O - https://github.com/screwdriver-cd/aws-consumer-service/releases/latest \
        egrep -o '/screwdriver-cd/aws-consumer-service/releases/download/v[0-9.]*/aws-consumer-service_linux_amd64' \
        wget --base=http://github.com/ -i - -O service \
    chmod +x ./service
    cd ..
}

main() {
    
    check_dependencies

    read_input "$@"

    check_svc_vars
  
    get_consumer_svc_pkg

    run_tf_cmd
}

main "$@" 