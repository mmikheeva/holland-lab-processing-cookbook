
while getopts i:o:p:d: flag
do
    case "${flag}" in
        i) INSTRUCTIONS_PATH=${OPTARG};;
        o) REPORT_PATH=${OPTARG};;
        p) PROCESSING_PATH=${OPTARG};;
        d) INPUT_PATH=${OPTARG};;
    esac
done

cookbook_report=${REPORT_PATH}
rm -f ${cookbook_report}
touch ${cookbook_report}

# define header and create empty report

instructions_tmp=()
header_tmp=()

instructions=$(cat ${INSTRUCTIONS_PATH} | tail -n +2)
while IFS= read -r instruction_line; do
    path_pattern=$(echo "${instruction_line}" | cut -d "," -f4)
    report_pattern=$(echo "${instruction_line}" | cut -d "," -f5)
    parameter_report=$(echo "${instruction_line}" | cut -d "," -f7 | sed "s/\r//g")
    processing_step=$(echo "${instruction_line}" | cut -d "," -f1)
        
    if [[ $(ls ${PROCESSING_PATH} | grep -e "${path_pattern}") ]]; then
    path_pattern_list=$(ls ${PROCESSING_PATH} | grep -e "${path_pattern}")
    for path_pattern_select in $(echo "${path_pattern_list}"); do
    if [[ $(ls ${PROCESSING_PATH}/${path_pattern_select} | grep -e "${report_pattern}") ]]; then
        parameter_prefix=$(echo "${path_pattern_select}" | sed -E "s/^[^_]*_(.*)/\1/; t; s/.*//" | sed "s/[.]/_/g; s/-/_/g")
        if [[ -n "${parameter_prefix}" ]]; then 
            parameter_prefix="_"${parameter_prefix}
        fi
        parameter_report_tmp=${processing_step}"_"${parameter_report}${parameter_prefix}

        instruction_line_tmp=$(echo "${instruction_line}" | sed "s/${path_pattern},${report_pattern}/${path_pattern_select},${report_pattern}/g")
        instruction_line_tmp=$(echo "${instruction_line_tmp}" | sed "s/,${parameter_report}/,${parameter_report_tmp}/g")
        
        header_tmp+=("${parameter_report_tmp}")
        instructions_tmp+=("${instruction_line_tmp}")
    fi
    done
    fi
done <<< "${instructions}"

instructions_tmp=$(printf "%s\n" "${instructions_tmp[@]}")
instructions=${instructions_tmp}
unset instructions_tmp

mapfile -t header_tmp < <(printf "%s\n" "${header_tmp[@]}" | uniq)
    header_write_cmd="echo Sample"$(printf ",%s" "${header_tmp[@]}")
    parameter_write_cmd="echo \${sample}"$(printf ",\${%s}" "${header_tmp[@]}")
    parameter_unset_cmd=$(printf "unset %s\n" "${header_tmp[@]}")
unset header_tmp

eval "${header_write_cmd}" >> ${cookbook_report}

# run per each sample

cd "${PROCESSING_PATH}"
samples=$(ls ${INPUT_PATH} | grep -E "\.fastq$|\.fq$|\.fastq\.gz$|\.fq\.gz|\.bam$|\.sam$")
samples=$(echo "${samples}" | sed "s/[.]fastq.*//g; s/[.]fq.*//g; s/[.]bam.*//g; s/[.]sam.*//g")

for sample in $(echo "${samples}"); do 

eval $(echo "${parameter_unset_cmd}")

while IFS= read -r instruction_line; do
unset report
    path_pattern=$(echo "${instruction_line}" | cut -d "," -f4)
    report_pattern=$(echo "${instruction_line}" | cut -d "," -f5)
    parameter_pattern=$(echo "${instruction_line}" | cut -d "," -f6)
    parameter_report=$(echo "${instruction_line}" | cut -d "," -f7 | sed "s/\r//g")

    if [[ $(ls ${PROCESSING_PATH} | grep -e "${path_pattern}") ]]; then
    if [[ $(ls ${PROCESSING_PATH}/${path_pattern} | grep -e "${report_pattern}" | grep -e "${sample}") ]]; then
        basename=${sample}
        report=$(ls ${PROCESSING_PATH}/${path_pattern} | grep -e "${report_pattern}" | grep -e "${sample}")
    else
        basename=$(echo "${sample}" | sed "s/_R[1-2][.].*//g; s/_R[1-2]_.*//g; s/_[1-2][.].*//g; s/_[1-2]_.*//g")
        if [[ $(ls ${PROCESSING_PATH}/${path_pattern} | grep -e "${report_pattern}" | grep -e "${basename}") ]]; then
        report=$(ls ${PROCESSING_PATH}/${path_pattern} | grep -e "${report_pattern}" | grep -e "${basename}")
        fi
    fi
    if [[ -n "${report}" ]]; then
        load_report=$(cat ${PROCESSING_PATH}/${path_pattern}/${report})
        load_parameter=$(echo "${load_report}" | grep -e "${parameter_pattern}" | sed "s/.*${parameter_pattern}//g" | sed "s/ //g" | sed "s/\t//g" | sed "s/,//g" | sed "s/(.*)//g")
        if [[ -z "${load_parameter}" ]]; then 
        load_parameter=0
        fi
        eval $(echo "${parameter_report}=\$((${parameter_report} + ${load_parameter}))")
    fi
    fi 
done <<< "${instructions}"

eval "${parameter_write_cmd}" >> ${cookbook_report}
done




















