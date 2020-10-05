#!/bin/bash
# eggd_athena 1.0.0

main() {

    # download inputs
    dx download "$panel_bed"
    dx download "$exons_nirvana"
    dx download "$pb_bed"

    if [ ${build+x} ]; then
        echo "BUILD FILE PASSED"
        dx download "$build"
    fi

    # download SNPs if given to SNPs dir
    mkdir snps && cd snps

    for i in "${!snps[@]}"
    do
        dx download "${snps[$i]}"
    done
    
    ls
    cd ~/

    # set up bedtools
    gunzip bedtools.static.binary.gz
    mv bedtools.static.binary bedtools
    chmod a+x bedtools
    sudo mv bedtools /usr/local/bin

    # install python3.8
    gunzip Miniconda3-latest-Linux-x86_64.sh.gz
    bash ~/Miniconda3-latest-Linux-x86_64.sh -b

    # unzip athena and install requirements
    # unzip athena-master.zip
    # sudo chmod -R 775 athena
    # ./miniconda3/bin/pip install -r athena/requirements.txt

    # DEVELOPMENT - unzip athena-devlopment and install requirements
    unzip athena-development.zip
    sudo chmod -R 775 athena-development
    ./miniconda3/bin/pip install -qr athena-development/requirements.txt

    echo "Finished setup."

    # annotate bed file
    bash ./athena-development/bin/annotate_bed.sh -i "$panel_bed_name" -g "$exons_nirvana_name" -b "$pb_bed_name"
    ls
    annotated_bed=$(ls ./*_annotated.bed)

    # if sample naming given replace spaces with "_"
    if [ "$name" ]; then name=${name// /_}; fi

    # build string of inputs to pass to stats script
    stats_args=""

    if [ "$thresholds" ]; then stats_args+=" --thresholds $thresholds"; fi
    if [ "$build_name" ]; then stats_args+=" --build $build_name"; fi
    if [ "$name" ]; then stats_args+=" --outfile ${name}"; fi
    
    stats_cmd="--file $annotated_bed"
    stats_cmd+=$stats_args
    echo "stats cmd" $stats_cmd
    
    # generate single sample stats
    ./miniconda3/bin/python ./athena-development/bin/coverage_stats_single.py $stats_cmd
        
    exon_stats=$(ls ./athena-development/output/*exon_stats.tsv)
    gene_stats=$(ls ./athena-development/output/*gene_stats.tsv)

    # build string of inputs for report script
    report_args=""

    if [ "$cutoff_threshold" ]; then report_args+=" --threshold $cutoff_threshold"; fi
    if [ "$name" ]; then report_args+=" --sample_name $name"; fi
    if [ "${!snps[@]}" ]; then 
        snp_vcfs=$(find ~/snps/ -name "*.vcf")
        echo $snp_vcfs
        report_args+=" --snps $snp_vcfs";
    fi

    report_cmd="./athena-development/bin/coverage_report_single.py --exon_stats $exon_stats --gene_stats $gene_stats --raw_coverage $annotated_bed"
    report_cmd+=$report_args
    echo "report cmd" $report_cmd

    # generate report
    ./miniconda3/bin/python $report_cmd
    
    report=$(ls ./athena-development/output/*coverage_report.html)

    echo "Completed. Uploading files"

    exon_stats=$(dx upload $exon_stats --brief)
    gene_stats=$(dx upload $gene_stats --brief)
    report=$(dx upload $report --brief)
    annotated_bed=$(dx upload $annotated_bed --brief)

    dx-jobutil-add-output exon_stats "$exon_stats" --class=file
    dx-jobutil-add-output gene_stats "$gene_stats" --class=file
    dx-jobutil-add-output report "$report" --class=file
    dx-jobutil-add-output annotated_bed "$annotated_bed" --class=file
}
