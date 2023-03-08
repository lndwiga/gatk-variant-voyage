# #####################################################################
#   A Snakemake pipeline for variant calling from illumina sequences
# #####################################################################


# dependencies
# *********************************************************************
# configuration file
configfile: "workflow/config.yaml"


# global wild cards of sample and matepair list
# - this assumes that all fastq files have the SampleName_R1.fastq.gz and SampleName_R2.fastq.gz format
# - If not, they might have the SampleName_S1_L001_R1_001.fastq.gz and SampleName_S1_L001_R2_001.fastq.gz format
# - In this case, rename the files running the following command in your terminal, at the top level of the project:
# python3 workflow/rename_fastq_files.py
(SAMPLES,) = glob_wildcards(config["input"]["fastq"] + "{sample}_R1.fastq.gz")


# a list of all output files
# *********************************************************************
rule all:
    input:
        # ------------------------------------
        # get_genome_data
        config["get_genome_data"]["fasta"],
        config["get_genome_data"]["gff"],
        # ------------------------------------
        # genome_dict
        config["get_genome_data"]["dict"],
        # config["get_genome_data"]["regions"],
        # ------------------------------------
        # samtools_index
        config["samtools_index"]["fasta_idx"],
        # ------------------------------------        
        # bedops_gff2bed
        config["bedops_gff2bed"]["bed"],
        # ------------------------------------
        # trimmomaticS,
        expand(config["trimmomatic"]["dir"] + "{sample}_R1.fastq.gz", sample=SAMPLES),
        expand(config["trimmomatic"]["dir"] + "{sample}_R2.fastq.gz", sample=SAMPLES),
        expand(
            config["trimmomatic"]["dir"] + "{sample}_R1.unpaired.fastq.gz",
            sample=SAMPLES,
        ),
        expand(
            config["trimmomatic"]["dir"] + "{sample}_R2.unpaired.fastq.gz",
            sample=SAMPLES,
        ),
        # ------------------------------------
        # bwa_index
        config["bwa"]["index"],
        # ------------------------------------
        # bwa_mem
        expand(config["bwa"]["dir"] + "{sample}.bam", sample=SAMPLES),
        # ------------------------------------
        # gatk_clean
        expand(config["gatk_clean"]["dir"] + "{sample}.bam", sample=SAMPLES),
        # ------------------------------------
        # gatk_sort
        expand(config["gatk_sort"]["dir"] + "{sample}.bam", sample=SAMPLES),
        # ------------------------------------
        # gatk_markdup
        expand(config["gatk_markdup"]["dir"] + "{sample}.bam", sample=SAMPLES),
        expand(
            config["gatk_markdup"]["metrics"] + "{sample}.metrics.txt", sample=SAMPLES
        ),
        # ------------------------------------
        # samtools
        expand(config["samtools_view"]["dir"] + "{sample}.bam", sample=SAMPLES),
        expand(config["samtools_view"]["dir"] + "{sample}.bam.bai", sample=SAMPLES),
        # ------------------------------------
        # samtools_idxstats / samtools_flagstats
        expand(
            config["samtools_stats"]["dir"] + "{sample}.bam.idxstats.txt",
            sample=SAMPLES,
        ),
        expand(
            config["samtools_stats"]["dir"] + "{sample}.bam.flagstat.txt",
            sample=SAMPLES,
        ),
        # # ------------------------------------
        # # samtools_mapping_stats
        # expand(
        #     config["mapping_stats"]["dir"] + "{sample}.bam.idxstats.txt",
        #     sample=SAMPLES,
        # ),
        # expand(
        #     config["mapping_stats"]["dir"] + "{sample}.bam.flagstats.txt",
        #     sample=SAMPLES,
        # ),
        # # ------------------------------------
        # # bcftools_variant_calling
        # expand(config["bcftools"]["dir"] + "{sample}.vcf.gz", sample=SAMPLES),
        # # ------------------------------------
        # # snpeff_annotate_vcf
        # expand(config["snpEff"]["dir"] + "{sample}.vcf.gz", sample=SAMPLES),
        # # ------------------------------------
        # # snpsift_filter_vcf
        # expand(config["snpSift"]["dir"] + "{sample}.allele.txt", sample=SAMPLES),
        # expand(config["snpSift"]["dir"] + "{sample}.allele.freq.txt", sample=SAMPLES),


# genome data - download genome data
# *********************************************************************
rule get_genome_data:
    input:
        genome=config["input"]["genome"]["fasta"],
        gff=config["input"]["genome"]["gff"],
    output:
        genome=config["get_genome_data"]["fasta"],
        gff=config["get_genome_data"]["gff"],
    run:
        shell(  # cp - copy genome fasta file from snpeff database location
            """
            cp -f {input.genome} {output.genome}
            """
        )
        shell(  # cp - copy annotation file from snpeff database location
            """
            cp -f {input.gff} {output.gff}
            """
        )


# genome data - download genome data
# *********************************************************************
rule gatk_genome_dict:
    input:
        genome=rules.get_genome_data.output.genome,
    output:
        genome_dict=config["get_genome_data"]["dict"],
    conda:
        config["conda_env"]["gatk"]
    shell:
        """
        gatk CreateSequenceDictionary \
        --REFERENCE {input.genome} \
        --OUTPUT {output.genome_dict}
        """


# samtools index - index genome fasta file
# *********************************************************************s
rule samtools_index:
    input:
        rules.get_genome_data.output.genome,
    output:
        config["samtools_index"]["fasta_idx"],
    wrapper:
        "master/bio/samtools/faidx"


# bedops - convert genome GFF to BED
# *********************************************************************
rule bedops_gff2bed:
    input:
        rules.get_genome_data.output.gff,
    output:
        config["bedops_gff2bed"]["bed"],
    params:
        feature=config["bedops_gff2bed"]["feature"],
    conda:
        config["conda_env"]["bedops"]
    shell:
        """
        convert2bed --input=gff --output=bed < {input} | \
            grep -e {params.feature} > {output}
        """


# trimmomatic - clip illumina adapters, paired end mode
# *********************************************************************
rule trimmomatic:
    input:
        r1=config["input"]["fastq"] + "{sample}_R1.fastq.gz",
        r2=config["input"]["fastq"] + "{sample}_R2.fastq.gz",
    output:
        r1=config["trimmomatic"]["dir"] + "{sample}_R1.fastq.gz",
        r2=config["trimmomatic"]["dir"] + "{sample}_R2.fastq.gz",
        r1_unpaired=config["trimmomatic"]["dir"] + "{sample}_R1.unpaired.fastq.gz",
        r2_unpaired=config["trimmomatic"]["dir"] + "{sample}_R2.unpaired.fastq.gz",
    params:
        trimmer=config["trimmomatic"]["trimmer"],
        extra=config["trimmomatic"]["extra"],
    log:
        config["trimmomatic"]["dir"] + "log/{sample}.log",
    wrapper:
        "master/bio/trimmomatic/pe"


# bwa - generate bwa genome-index files for mapping
# *********************************************************************
rule bwa_index:
    input:
        genome=rules.get_genome_data.output.genome,
    output:
        index=touch(config["bwa"]["index"]),
    conda:
        config["conda_env"]["bwa"]
    shell:
        """
        bwa index -p {output.index} {input.genome}
        """


# bwa - map reads to genome
# *********************************************************************
rule bwa_mem:
    input:
        reads=[
            rules.trimmomatic.output.r1,
            rules.trimmomatic.output.r2,
        ],
        idx=rules.bwa_index.output,
    output:
        config["bwa"]["dir"] + "{sample}.bam",
    log:
        config["bwa"]["log"] + "{sample}.log",
    params:
        extra=r"-R '@RG\tID:{sample}\tSM:{sample}'",
        sorting="none",
        sort_extra="",  # Extra args for samtools/picard.
    threads: config["threads"]
    wrapper:
        "master/bio/bwa/mem"


# gatk - clean sam file (remove artifacts in SAM/BAM files)
# *********************************************************************
rule gatk_clean_sam:
    input:
        bam=rules.bwa_mem.output,
        genome=rules.get_genome_data.output.genome,
    output:
        clean=config["gatk_clean"]["dir"] + "{sample}.bam",
    params:
        java_opts="",
    conda:
        config["conda_env"]["gatk"]
    shell:
        """
        gatk CleanSam \
            -R {input.genome} \
            -I {input.bam} \
            -O {output.clean}
        """


# gatk - sort sam
# *********************************************************************
rule gatk_sort_sam:
    input:
        bam=rules.gatk_clean_sam.output.clean,
        genome=rules.get_genome_data.output.genome,
    output:
        sorted=config["gatk_sort"]["dir"] + "{sample}.bam",
    params:
        java_opts="",
    conda:
        config["conda_env"]["gatk"]
    shell:
        """
        gatk SortSam \
            -R {input.genome} \
            -I {input.bam} \
            -O {output.sorted} \
            --SORT_ORDER coordinate
        """


# gatk - mark duplicates
# *********************************************************************
rule gatk_markdup:
    input:
        bam=rules.gatk_sort_sam.output.sorted,
    output:
        bam=config["gatk_markdup"]["dir"] + "{sample}.bam",
        metrics=config["gatk_markdup"]["metrics"] + "{sample}.metrics.txt",
    log:
        config["gatk_markdup"]["log"] + "{sample}.log",
    params:
        extra="",
        java_opts="",
        #spark_runner="",  # optional, local by default
        #spark_master="",  # optional
        #spark_extra="", # optional
    threads: 8
    wrapper:
        "master/bio/gatk/markduplicatesspark"


# samtools - view (keep reads in core genome regions of BED file)
# *********************************************************************
rule samtools_view:
    input:
        bam=rules.gatk_markdup.output.bam,
        genome=rules.get_genome_data.output.genome,
        core_genome=config["samtools_view"]["core"],
    output:
        bam=config["samtools_view"]["dir"] + "{sample}.bam",
        index=config["samtools_view"]["dir"] + "{sample}.bam.bai",
    log:
        config["samtools_view"]["log"] + "{sample}.log",
    threads: config["threads"]
    conda:
        config["conda_env"]["samtools"]
    shell:
        """
        samtools view \
            -b \
            -h \
            -@ {threads} \
            -T {input.genome} \
            -L {input.core_genome} \
            {input.bam} \
            > {output.bam}
        samtools index {output.bam} {output.index}
        """


# samtools - idxstats (get mapping-quality statistics from BAM file)
# *********************************************************************
rule samtools_idxstats:
    input:
        rules.samtools_view.output.bam,
    output:
        config["samtools_stats"]["dir"] + "{sample}.bam.idxstats.txt",
    conda:
        config["conda_env"]["samtools"]
    shell:
        """
        samtools idxstats {input} > {output}
        """


# samtools - flagstats (get mapping-quality statistics from BAM file)
# *********************************************************************
rule samtools_flagstat:
    input:
        rules.samtools_view.output.bam,
    output:
        config["samtools_stats"]["dir"] + "{sample}.bam.flagstat.txt",
    conda:
        config["conda_env"]["samtools"]
    shell:
        """
        samtools flagstat {input} > {output}
        """
