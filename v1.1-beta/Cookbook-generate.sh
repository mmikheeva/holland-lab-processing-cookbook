
while getopts i:o: flag
do
    case "${flag}" in
        i) INSTRUCTIONS_PATH=${OPTARG};;
        o) SCRIPT_PATH=${OPTARG};;
    esac
done

unset INSTRUCTIONS INPUT_PATH OUTPUT_PATH TOOL  
unset FASTA GTF THREADS REGION PREFIX  

instructions=$(cat ${INSTRUCTIONS_PATH})
cookbook_script=${SCRIPT_PATH}
rm -f ${cookbook_script}

define_input_path=$(echo "${instructions}" | grep -e "INPUT_PATH=")
define_output_path=$(echo "${instructions}" | grep -e "OUTPUT_PATH=")
eval "${define_input_path}" && eval "${define_output_path}"

touch ${cookbook_script}
echo "### Created on: $(date +"%Y-%m-%d %H:%M")" >> ${cookbook_script}
echo "### Created by: ${USER}" >> ${cookbook_script}
echo "" >> ${cookbook_script}

echo "cd ${OUTPUT_PATH}" >> ${cookbook_script}
echo "" >> ${cookbook_script}

# qc

section_head="QUALITY CONTROL" 
define_section=$(echo "${instructions}" | awk "/^== ${section_head} ==$/{flag=1; next} /^== / && flag {flag=0} flag" | tail -n +2)
define_tool=$(echo "${define_section}" | grep -e "TOOL=")
eval ${define_tool}
if [[ ${TOOL} != Skip ]]; then

echo "# qc" >> ${cookbook_script}
echo "" >> ${cookbook_script}

echo "out_dir=${OUTPUT_PATH}/qc && mkdir -p \${out_dir}" >> ${cookbook_script}
echo "samples=\$(ls ${INPUT_PATH}/* | grep -E \"\.fastq$|\.fq$|\.fastq\.gz$|\.fq\.gz$\")" >> ${cookbook_script}

if [[ ${TOOL} == FastQC ]]; then
    ARGS=$(echo "${define_section}" | awk "/> ${TOOL} parameters/{flag=1} flag && NF==0{flag=0} flag" | \
    tail -n +3 | sed "s/#.*//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    echo "for sample in \$(echo \${samples}); do" >> ${cookbook_script}
    echo "basename=\$(basename -a \${sample} | sed \"s/\.fastq\$//g; s/\.fq\$//g; s/\.fastq\.gz\$//g; s/\.fq\.gz\$//g\" | uniq)" >> ${cookbook_script}    
    echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}

    echo -e "fastqc --outdir \${out_dir} --dir \${out_dir} ${ARGS} \\\\\\n\${sample}" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
    echo "done" >> ${cookbook_script}
fi

echo "" >> ${cookbook_script}
fi

# trimming

section_head="TRIMMING" 
define_section=$(echo "${instructions}" | awk "/^== ${section_head} ==$/{flag=1; next} /^== / && flag {flag=0} flag" | tail -n +2)
define_tool=$(echo "${define_section}" | grep -e "TOOL=")
eval ${define_tool}
if [[ ${TOOL} != Skip ]]; then

echo "# trimming" >> ${cookbook_script}
echo "" >> ${cookbook_script}

echo "out_dir=${OUTPUT_PATH}/trim && mkdir -p \${out_dir}" >> ${cookbook_script}
echo "samples=\$(ls ${INPUT_PATH}/* | grep -E \"\.fastq$|\.fq$|\.fastq\.gz$|\.fq\.gz$\")" >> ${cookbook_script}

if [[ ${TOOL} == TrimGalore ]]; then
    ARGS=$(echo "${define_section}" | awk "/> ${TOOL} parameters/{flag=1} flag && NF==0{flag=0} flag" | \
    tail -n +3 | sed "s/#.*//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    if [[ ${ARGS} == *--paired* ]]; then        
        echo "basenames=\$(basename -a \${samples} | sed \"s/_R[1-2][.].*//g; s/_R[1-2]_.*//g; s/_[1-2][.].*//g; s/_[1-2]_.*//g\" | uniq)" >> ${cookbook_script}
        echo "for basename in \$(echo \${basenames}); do" >> ${cookbook_script}
        echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}
        
        echo "sample_r1=\$(echo \"\${samples}\" | grep -e \"\${basename}\" | grep -E \"_R1[.].*|_R1_.*|_1[.].*|_1_.*\")" >> ${cookbook_script}
        echo "sample_r2=\$(echo \"\${samples}\" | grep -e \"\${basename}\" | grep -E \"_R2[.].*|_R2_.*|_2[.].*|_2_.*\")" >> ${cookbook_script}
        echo -e "trim_galore --output_dir \${out_dir} ${ARGS} \\\\\\n\${sample_r1} \\\\\\n\${sample_r2}" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
    else
        echo "for sample in \$(echo \${samples}); do" >> ${cookbook_script}
        echo "basename=\$(basename -a \${sample} | sed \"s/\.fastq\$//g; s/\.fq\$//g; s/\.fastq\.gz\$//g; s/\.fq\.gz\$//g\" | uniq)" >> ${cookbook_script}    
        echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}

        echo -e "trim_galore --output_dir \${out_dir} ${ARGS} \\\\\\n\${sample}" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
    fi
    echo "done" >> ${cookbook_script}
fi

INPUT_PATH=${OUTPUT_PATH}/trim
echo "" >> ${cookbook_script}
fi

# build alignment index

section_head="ALIGNMENT INDEX" 
define_section=$(echo "${instructions}" | awk "/^== ${section_head} ==$/{flag=1; next} /^== / && flag {flag=0} flag" | tail -n +2)
define_tool=$(echo "${define_section}" | grep -e "TOOL=")
eval ${define_tool}
if [[ ${TOOL} != Skip ]]; then

echo "# build alignment index" >> ${cookbook_script}
echo "" >> ${cookbook_script}

if [[ ${TOOL} == Bismark ]]; then
    echo "genome_idx=${OUTPUT_PATH}/bismark-idx && mkdir -p \${genome_idx}" >> ${cookbook_script}

    ARGS=$(echo "${define_section}" | awk "/> ${TOOL} parameters/{flag=1} flag && NF==0{flag=0} flag" | \
    tail -n +3 | sed "s/#.*//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    FASTA=$(echo "${ARGS}" | sed -n "s/.*\(--genome_fa [^ ]*\).*/\1/p" | sed "s/--genome_fa//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    echo "cp ${FASTA} \${genome_idx}/" >> ${cookbook_script}
    
    ARGS=$(echo "${ARGS}" | sed "s/--genome_fa [^ ]\+//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    echo -e "bismark_genome_preparation ${ARGS} \\\\\\n\${genome_idx}/" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
fi

if [[ ${TOOL} == STAR ]]; then
    echo "genome_idx=${OUTPUT_PATH}/star-idx && mkdir -p \${genome_idx}" >> ${cookbook_script}
    
    ARGS=$(echo "${define_section}" | awk "/> ${TOOL} parameters/{flag=1} flag && NF==0{flag=0} flag" | \
    tail -n +3 | sed "s/#.*//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    echo "STAR --runMode genomeGenerate --genomeDir \${genome_idx} ${ARGS}" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
fi

echo "" >> ${cookbook_script}
fi
    
# alignment

section_head="GENOME ALIGNMENT" 
define_section=$(echo "${instructions}" | awk "/^== ${section_head} ==$/{flag=1; next} /^== / && flag {flag=0} flag" | tail -n +2)
define_tool=$(echo "${define_section}" | grep -e "TOOL=")
eval ${define_tool}
if [[ ${TOOL} != Skip ]]; then

echo "# alignment to genome" >> ${cookbook_script}
echo "" >> ${cookbook_script}

echo "out_dir=${OUTPUT_PATH}/map && mkdir -p \${out_dir}" >> ${cookbook_script}
echo "samples=\$(ls ${INPUT_PATH}/* | grep -E \"\.fastq$|\.fq$|\.fastq\.gz$|\.fq\.gz$\")" >> ${cookbook_script}

if [[ ${TOOL} == Bismark ]]; then
    ARGS=$(echo "${define_section}" | awk "/> ${TOOL} parameters/{flag=1} flag && NF==0{flag=0} flag" | \
    tail -n +3 | sed "s/#.*//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    if [[ ${ARGS} == *"-1 -2"* ]]; then        
        echo "basenames=\$(basename -a \${samples} | sed \"s/_R[1-2][.].*//g; s/_R[1-2]_.*//g; s/_[1-2][.].*//g; s/_[1-2]_.*//g\" | uniq)" >> ${cookbook_script}
        echo "for basename in \$(echo \${basenames}); do" >> ${cookbook_script}
        echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}

        echo "sample_r1=\$(echo \"\${samples}\" | grep -e \"\${basename}\" | grep -E \"_R1[.].*|_R1_.*|_1[.].*|_1_.*\")" >> ${cookbook_script}
        echo "sample_r2=\$(echo \"\${samples}\" | grep -e \"\${basename}\" | grep -E \"_R2[.].*|_R2_.*|_2[.].*|_2_.*\")" >> ${cookbook_script}
        
        ARGS=$(echo "${ARGS}" | sed "s/-1 -2//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
        echo "bismark --output_dir \${out_dir} --temp_dir \${out_dir} ${ARGS} -1 \${sample_r1} -2 \${sample_r2}" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
    else
        echo "for sample in \$(echo \${samples}); do" >> ${cookbook_script}
        echo "basename=\$(basename -a \${sample} | sed \"s/\.fastq\$//g; s/\.fq\$//g; s/\.fastq\.gz\$//g; s/\.fq\.gz\$//g\" | uniq)" >> ${cookbook_script}    
        echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}

        echo -e "bismark --output_dir \${out_dir} --temp_dir \${out_dir} ${ARGS} \\\\\\n\${sample}" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
    fi
    echo "out_bam=\$(ls \${out_dir}/* | grep -E \"\.bam$|\.sam$\" | grep -e \"\${basename}\")" >> ${cookbook_script}  
    echo "tmp_dir=\$(mktemp -d \${out_dir}/tmp.XXX)" >> ${cookbook_script}

    THREADS=$(echo "${ARGS}" | sed -n "s/.*\(--parallel [^ ]*\).*/\1/p" | sed "s/parallel/threads/g")    
    echo "samtools sort ${THREADS} -T \${out_dir} -o \${tmp_dir}/temp.bam \${out_bam} && mv \${tmp_dir}/temp.bam \${out_bam}" >> ${cookbook_script}
    echo "samtools index ${THREADS} \${out_bam}" >> ${cookbook_script}
    echo "rm -r \${tmp_dir}" >> ${cookbook_script}
    echo "done" >> ${cookbook_script}
fi

if [[ ${TOOL} == STAR ]]; then
    ARGS=$(echo "${define_section}" | awk "/> ${TOOL} parameters/{flag=1} flag && NF==0{flag=0} flag" | \
    tail -n +3 | sed "s/#.*//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    
    if [[ ${ARGS} == *--paired* ]]; then
        echo "basenames=\$(basename -a \${samples} | sed \"s/_R[1-2][.].*//g; s/_R[1-2]_.*//g; s/_[1-2][.].*//g; s/_[1-2]_.*//g\" | uniq)" >> ${cookbook_script}
        echo "for basename in \$(echo \${basenames}); do" >> ${cookbook_script}
        echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}
        
        echo "sample_r1=\$(echo \"\${samples}\" | grep -e \"\${basename}\" | grep -E \"_R1[.].*|_R1_.*|_1[.].*|_1_.*\")" >> ${cookbook_script}
        echo "sample_r2=\$(echo \"\${samples}\" | grep -e \"\${basename}\" | grep -E \"_R2[.].*|_R2_.*|_2[.].*|_2_.*\")" >> ${cookbook_script}

        ARGS=$(echo "${ARGS}" | sed "s/--paired//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
        echo "STAR --outFileNamePrefix \${out_dir}/\${basename}. --outSAMattrRGline ID:\${basename} SM:\${basename} ${ARGS} --readFilesIn \${sample_r1} \${sample_r2}" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
    else
        echo "for sample in \$(echo \${samples}); do" >> ${cookbook_script}
        echo "basename=\$(basename -a \${sample} | sed \"s/\.fastq\$//g; s/\.fq\$//g; s/\.fastq\.gz\$//g; s/\.fq\.gz\$//g\" | uniq)" >> ${cookbook_script}    
        echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}

        echo "STAR --outFileNamePrefix \${out_dir}/\${basename}. --outSAMattrRGline ID:\${basename} SM:\${basename} ${ARGS} --readFilesIn \${sample}" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
    fi
    echo "out_bam=\$(ls \${out_dir}/* | grep -E \"\.bam$|\.sam$\" | grep -e \"\${basename}\")" >> ${cookbook_script}  
    THREADS=$(echo "${ARGS}" | sed -n "s/.*\(--outBAMsortingThreadN [^ ]*\).*/\1/p" | sed "s/outBAMsortingThreadN/threads/g")    
    echo "samtools index ${THREADS} \${out_bam}" >> ${cookbook_script}
    echo "done" >> ${cookbook_script}
fi

INPUT_PATH=${OUTPUT_PATH}/map
echo "" >> ${cookbook_script}
fi
       
# deduplication
    
section_head="DEDUPLICATION" 
define_section=$(echo "${instructions}" | awk "/^== ${section_head} ==$/{flag=1; next} /^== / && flag {flag=0} flag" | tail -n +2)
define_tool=$(echo "${define_section}" | grep -e "TOOL=")
eval ${define_tool}
if [[ ${TOOL} != Skip ]]; then

echo "# deduplication" >> ${cookbook_script}
echo "" >> ${cookbook_script}

echo "out_dir=${OUTPUT_PATH}/dedup && mkdir -p \${out_dir}" >> ${cookbook_script}
echo "samples=\$(ls ${INPUT_PATH}/* | grep -E \"\.bam$|\.sam$\")" >> ${cookbook_script}

if [[ ${TOOL} == Bismark ]]; then
    echo "for sample in \$(echo \${samples}); do" >> ${cookbook_script}
    echo "basename=\$(basename -a \${sample} | sed \"s/\.bam\$//g; s/\.sam\$//g\" )" >> ${cookbook_script}
    echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}

    echo "tmp_dir=\$(mktemp -d \${out_dir}/tmp.XXX)" >> ${cookbook_script}

    ARGS=$(echo "${define_section}" | awk "/> ${TOOL} parameters/{flag=1} flag && NF==0{flag=0} flag" | \
    tail -n +3 | sed "s/#.*//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    THREADS=$(echo "${ARGS}" | sed -n "s/.*\(--threads [^ ]*\).*/\1/p")    
    ARGS=$(echo "${ARGS}" | sed "s/--threads [^ ]\+//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")

    echo "samtools sort -n -o \${tmp_dir}/temp.bam -T \${tmp_dir} ${THREADS} \${sample}" >> ${cookbook_script}
    echo -e "deduplicate_bismark --output_dir \${out_dir} --outfile \${basename} ${ARGS} \\\\\\n\${tmp_dir}/temp.bam" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
    echo "rm \${tmp_dir}/temp.bam" >> ${cookbook_script}
     
    echo "out_bam=\$(ls \${out_dir}/* | grep -E \"\.bam$|\.sam$\" | grep -e \"\${basename}\")" >> ${cookbook_script}

    echo "samtools sort ${THREADS} -T \${out_dir} -o \${tmp_dir}/temp.bam \${out_bam} && mv \${tmp_dir}/temp.bam \${out_bam}" >> ${cookbook_script}
    echo "samtools index ${THREADS} \${out_bam}" >> ${cookbook_script}
    echo "rm -r \${tmp_dir}" >> ${cookbook_script}
    echo "done" >> ${cookbook_script}
fi

INPUT_PATH=${OUTPUT_PATH}/dedup
echo "" >> ${cookbook_script}
fi

# reads per region

section_head="READS PER REGION" 
define_section=$(echo "${instructions}" | awk "/^== ${section_head} ==$/{flag=1; next} /^== / && flag {flag=0} flag" | tail -n +2)
define_tool=$(echo "${define_section}" | grep -e "TOOL=")
eval ${define_tool}

if [[ ${TOOL} == Samtools ]]; then
echo "# reads within specified region" >> ${cookbook_script}
echo "" >> ${cookbook_script}

ARGS=$(echo "${define_section}" | awk "/> ${TOOL} parameters/{flag=1} flag && NF==0{flag=0} flag" | \
tail -n +3 | sed "s/#.*//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
THREADS=$(echo "${ARGS}" | sed -n "s/.*\(--threads [^ ]*\).*/\1/p") 
REGION=$(echo "${ARGS}" | sed -n "s/.*\(-R [^ ]*\).*/\1/p")
PREFIX=$(echo "${REGION}" | sed "s/-R //g" | sed "s/:/_/g" | sed "s/-/_/g") 
    if [[ -n "${PREFIX}" ]]; then 
        PREFIX="_"${PREFIX}
    fi

echo "out_dir=${OUTPUT_PATH}/bam${PREFIX} && mkdir -p \${out_dir}" >> ${cookbook_script}
echo "samples=\$(ls ${INPUT_PATH}/* | grep -E \"\.bam$|\.sam$\")" >> ${cookbook_script}
echo "for sample in \$(echo \${samples}); do" >> ${cookbook_script}
echo "basename=\$(basename -a \${sample} | sed \"s/\.bam\$//g; s/\.sam\$//g\" )" >> ${cookbook_script}
echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}
echo "tmp_dir=\$(mktemp -d \${out_dir}/tmp.XXX)" >> ${cookbook_script}

echo "samtools sort -o \${tmp_dir}/temp.bam -T \${tmp_dir} ${THREADS} \${sample}" >> ${cookbook_script}
echo "samtools index \${tmp_dir}/temp.bam" >> ${cookbook_script}
echo "samtools merge ${REGION} -o \${out_dir}/\${basename}.bam \${tmp_dir}/temp.bam" >> ${cookbook_script}
echo "samtools index \${out_dir}/\${basename}.bam" >> ${cookbook_script}
echo "echo \"Reads per region: \"\$(samtools idxstats \${out_dir}/\${basename}.bam | awk \"{s+=\\\$3} END {print s}\") >> \${out_dir}/\${basename}.reads-per-region-report.txt" >> ${cookbook_script}
echo "rm -r \${tmp_dir}" >> ${cookbook_script}
echo "done" >> ${cookbook_script}

INPUT_PATH=${OUTPUT_PATH}/bam${PREFIX}
echo "" >> ${cookbook_script}
fi

# methylation extraction

section_head="METHYLATION EXTRACTION" 
define_section=$(echo "${instructions}" | awk "/^== ${section_head} ==$/{flag=1; next} /^== / && flag {flag=0} flag" | tail -n +2)
define_tool=$(echo "${define_section}" | grep -e "TOOL=")
eval ${define_tool}
if [[ ${TOOL} != Skip ]]; then

echo "# methylation extraction" >> ${cookbook_script}
echo "" >> ${cookbook_script}

echo "out_dir=${OUTPUT_PATH}/methyl${PREFIX} && mkdir -p \${out_dir}" >> ${cookbook_script}
echo "samples=\$(ls ${INPUT_PATH}/* | grep -E \"\.bam$|\.sam$\")" >> ${cookbook_script}

if [[ ${TOOL} == Bismark ]]; then
    echo "for sample in \$(echo \${samples}); do" >> ${cookbook_script}
    echo "basename=\$(basename -a \${sample} | sed \"s/\.bam\$//g; s/\.sam\$//g\" )" >> ${cookbook_script}
    echo "if ls \${out_dir} | grep -q -e \"\${basename}\"; then continue; fi" >> ${cookbook_script}
    echo "tmp_dir=\$(mktemp -d \${out_dir}/tmp.XXX)" >> ${cookbook_script}

    ARGS=$(echo "${define_section}" | awk "/> ${TOOL} parameters/{flag=1} flag && NF==0{flag=0} flag" | \
    tail -n +3 | sed "s/#.*//g" | tr -s "[:space:]" " " | sed "s/^ //g"| sed "s/ $//g")
    THREADS=$(echo "${ARGS}" | sed -n "s/.*\(--parallel [^ ]*\).*/\1/p" | sed "s/--parallel/--threads/g") 

    echo "samtools sort -n -o \${tmp_dir}/\${basename}.bam -T \${tmp_dir} ${THREADS} \${sample}" >> ${cookbook_script}
    echo -e "bismark_methylation_extractor --output_dir \${out_dir} ${ARGS} \\\\\\n\${tmp_dir}/\${basename}.bam" | sed "s/ -/ \\\\\\n-/g" >> ${cookbook_script}
    echo "rm -r \${tmp_dir}" >> ${cookbook_script}
    echo "done" >> ${cookbook_script}
fi

echo "" >> ${cookbook_script}
fi







































