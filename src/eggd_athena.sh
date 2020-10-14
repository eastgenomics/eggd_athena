#!/bin/bash
# eggd_athena 1.0.0

set -exo pipefail

main() {

    # download inputs
    dx download "$panel_bed"
    dx download "$exons_nirvana"
    dx download "$pb_bed"

    if [ ${build+x} ]; then
        dx download "$build"
    fi

    # download SNPs if given to SNPs dir
    mkdir snps && cd snps
    
    for i in "${!snps[@]}"
    do
        dx download "${snps[$i]}"
    done

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
    # should include .zip of athena from releases
    unzip athena-*.zip
    sudo chmod -R 775 athena-*
    
    # install required python packages from local packages dir
    echo "Installing python packages"
    cd packages
    ~/miniconda3/bin/pip install -q certifi-* pytz-* python_dateutil-* pysam-* cycler-* kiwisolver-* Pillow* \
        retrying-* pyparsing-* numpy-* SQLAlchemy-* pandas-* pandasql-* matplotlib-* plotly-* pybedtools-*
    cd ~

    echo "Finished setup. Beginning analysis."
    echo "Annotating bed file."

    # annotate bed file
    bash ./athena-development/bin/annotate_bed.sh -i "$panel_bed_name" -g "$exons_nirvana_name" -b "$pb_bed_name"
    annotated_bed=$(find . -name "*_annotated.bed")

    # if sample naming given replace spaces with "_"
    if [ "$name" ]; then name=${name// /_}; fi

    # build string of inputs to pass to stats script
    stats_args=""

    if [ "$thresholds" ]; then stats_args+=" --thresholds $thresholds"; fi
    if [ "$build_name" ]; then stats_args+=" --build $build_name"; fi
    if [ "$name" ]; then stats_args+=" --outfile ${name}"; fi
    
    stats_cmd="--file $annotated_bed"
    stats_cmd+=$stats_args
    echo "Generating coverage stats with: " $stats_cmd
    
    # generate single sample stats
    time ./miniconda3/bin/python ./athena-development/bin/coverage_stats_single.py $stats_cmd
        
    exon_stats=$(find ./athena-development/output/ -name "*exon_stats.tsv")
    gene_stats=$(find ./athena-development/output/ -name "*gene_stats.tsv")

    # build string of inputs for report script
    report_args=""

    if [ "$cutoff_threshold" ]; then report_args+=" --threshold $cutoff_threshold"; fi
    if [ "$name" ]; then report_args+=" --sample_name $name"; fi
    if [ "$panel" = true ]; then report_args+=" --panel $panel_bed_name"; fi
    if [ "${!snps[@]}" ]; then 
        snp_vcfs=$(find ~/snps/ -name "*.vcf")
        echo $snp_vcfs
        report_args+=" --snps $snp_vcfs";
    fi

    report_cmd="./athena-development/bin/coverage_report_single.py --exon_stats $exon_stats --gene_stats $gene_stats --raw_coverage $annotated_bed --limit $limit"
    report_cmd+=$report_args
    echo "Generating report with: " $report_cmd

    # generate report
    time ./miniconda3/bin/python $report_cmd
    
    report=$(find ./athena-development/output/ -name "*coverage_report.html")

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
