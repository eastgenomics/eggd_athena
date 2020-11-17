#!/bin/bash
# eggd_athena 1.0.3

set -exo pipefail

main() {

    # download inputs
    dx download "$panel_bed"
    dx download "$exons_nirvana"

    # download mosdepth files
    for i in "${!mosdepth_files[@]}"
    do
        dx download "${mosdepth_files[$i]}"
    done

    # set per base and build files from downloaded mosdepth file array
    # if this is run with just per-base bed file in the array, build will
    # evaluate to an empty string and not be passed into the report script
    pb_bed=$(find . -name "*.per-base.bed.gz")
    build=$(find . -name "*.reference_build.txt")

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

    # get athena name with version from downloaded tar
    athena_dir=$(find . -name athena-*)
    athena_dir=${athena_dir/.tar.gz/}

    # untar athena and install requirements
    # should include tar of athena from releases
    tar -xf athena-*.tar.gz

    # -development tars get untarred to "athena", releases to "athena-release_ver"
    if test -d ./athena; then mv athena $athena_dir; fi
    sudo chmod -R 775 $athena_dir

    # install required python packages from local packages dir
    echo "Installing python packages"
    cd packages
    ~/miniconda3/bin/pip install -q certifi-* MarkupSafe-* pytz-* python_dateutil-* pysam-* cycler-* Jinja2-* kiwisolver-* \
    Pillow* retrying-* pyparsing-* numpy-* SQLAlchemy-* pandas-* pandasql-* matplotlib-* plotly-* pybedtools-*
    cd ~

    echo "Finished setup. Beginning analysis."
    echo "Annotating bed file."

    # annotate bed file
    bash $athena_dir/bin/annotate_bed.sh -i "$panel_bed_name" -g "$exons_nirvana_name" -b "$pb_bed"
    annotated_bed=$(find . -name "*_annotated.bed")

    # if sample naming given replace spaces with "_" and "/" with "-"
    if [ "$name" ]; then name=${name// /_}; fi
    if [ "$name" ]; then name=${name//\//-}; fi

    # build string of inputs to pass to stats script
    stats_args=""

    if [ "$thresholds" ]; then stats_args+=" --thresholds $thresholds"; fi
    if [ "$build_name" ]; then stats_args+=" --build $build"; fi
    if [ "$name" ]; then stats_args+=" --outfile ${name}"; fi

    stats_cmd="--file $annotated_bed"
    stats_cmd+=$stats_args
    echo "Generating coverage stats with: " $stats_cmd

    # generate single sample stats
    time ./miniconda3/bin/python ./$athena_dir/bin/coverage_stats_single.py $stats_cmd
 
    exon_stats=$(find ${athena_dir}/output/ -name "*exon_stats.tsv")
    gene_stats=$(find ${athena_dir}/output/ -name "*gene_stats.tsv")

    # build string of inputs for report script
    report_args=""

    if [ "$cutoff_threshold" ]; then report_args+=" --threshold $cutoff_threshold"; fi
    if [ "$name" ]; then report_args+=" --sample_name $name"; fi
    if [ "$panel" = true ]; then report_args+=" --panel $panel_bed_name"; fi
    if [ "$summary" = true ]; then report_args+=" --summary"; fi
    if [ "${!snps[@]}" ]; then 
        snp_vcfs=$(find ~/snps/ -name "*.vcf")
        echo $snp_vcfs
        report_args+=" --snps $snp_vcfs";
    fi

    report_cmd="$athena_dir/bin/coverage_report_single.py --exon_stats $exon_stats --gene_stats $gene_stats --raw_coverage $annotated_bed --limit $limit"
    report_cmd+=$report_args
    echo "Generating report with: " $report_cmd

    # generapythonte report
    time ./miniconda3/bin/python $report_cmd

    report=$(find ${athena_dir}/output/ -name "*coverage_report.html")

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
