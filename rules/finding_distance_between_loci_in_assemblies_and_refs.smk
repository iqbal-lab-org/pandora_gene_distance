import pysam
import editdistance
import pandas as pd

rule split_genes_from_vcf_ref:
    input:
        pandora_vcf_ref = pandora_vcf_ref
    output:
        all_genes_filepaths_in_vcf_ref = all_genes_filepaths_in_vcf_ref
    threads: 1
    resources:
        mem_mb = lambda wildcards, attempt: 1000 * attempt
    log:
        "logs/split_genes_from_vcf_ref.log"
    run:
        with pysam.FastxFile(input.pandora_vcf_ref) as fasta_file:
            for fasta_record in fasta_file:
                with open(f"{output_folder}/genes_from_vcf_ref/{fasta_record.name}.fa", "w") as fasta_record_file:
                    fasta_record_file.write(str(fasta_record))


rule get_truth_or_ref_gene_sequence_of_mosaic_gene:
    input:
         truth_or_ref = lambda wildcards: f"{assemblies_and_refs.xs(wildcards.id)['fasta']}",
         truth_or_ref_index = lambda wildcards: f"{assemblies_and_refs.xs(wildcards.id)['fasta']}.fai",
         sam_file = rules.map_gene_from_vcf_ref_to_truth_or_ref_using_bowtie.output.sam_file
    output:
         truth_or_ref_gene_sequence = f"{output_folder}/genes_from_truth_or_ref/{{gene}}~~~{{id}}.csv"
    threads: 1
    resources:
        mem_mb = lambda wildcards, attempt: 1000 * attempt
    log:
        "logs/get_truth_or_ref_gene_sequence_of_mosaic_gene/{gene}~~~{id}.log"
    run:
        with pysam.AlignmentFile(input.sam_file) as sam_file:
            sam_records = [sam_record for sam_record in sam_file]
        assert len(sam_records) == 1
        sam_record = sam_records[0]

        ref_or_truth_id = wildcards.id
        with open(output.truth_or_ref_gene_sequence, "w") as truth_or_ref_gene_sequence:
            if not sam_record.is_unmapped:
                status = "Mapped"
                contig = sam_record.reference_name
                start = sam_record.reference_start
                stop = sam_record.reference_end
                with pysam.FastaFile(filename = input.truth_or_ref, filepath_index=input.truth_or_ref_index) as truth_or_ref_fasta_file:
                    reference_seq = truth_or_ref_fasta_file.fetch(reference = contig)
                sequence = reference_seq[start:stop].upper()
            else:
                status = "Unmapped"
                contig = None
                start = None
                stop = None
                sequence = None

        df = pd.DataFrame({
            "status": [status],
            "ref_or_truth_id": [ref_or_truth_id],
            "contig": [contig],
            "start": [start],
            "stop": [stop],
            "sequence": [sequence]
        })
        df.to_csv(output.truth_or_ref_gene_sequence, index=False)


rule get_edit_distance_between_genes_of_truth_assemblies_and_ref:
    input:
         truth_gene = lambda wildcards: f"{output_folder}/genes_from_truth_or_ref/{{gene}}~~~{{truth_id}}.csv",
         ref_gene = lambda wildcards: f"{output_folder}/genes_from_truth_or_ref/{{gene}}~~~{{ref_id}}.csv",
    output:
         edit_distance_between_genes_of_truth_assemblies_and_ref = f"{output_folder}/edit_distances/{{gene}}~~~{{truth_id}}~~~{{ref_id}}.edit_distance.csv"
    threads: 1
    resources:
        mem_mb = lambda wildcards, attempt: 1000 * attempt
    log:
        "logs/get_edit_distance_between_genes_of_truth_assemblies_and_ref/{{gene}}~~~{{truth_id}}~~~{{ref_id}}.edit_distance.log"
    run:
        truth_gene_df = pd.read_csv(input.truth_gene)
        ref_gene_df = pd.read_csv(input.ref_gene)
        truth_and_ref_gene_df = truth_gene_df.join(ref_gene_df, lsuffix="_truth_gene", rsuffix="_ref_gene")

        if truth_and_ref_gene_df["status_truth_gene"][0] == "Mapped" and truth_and_ref_gene_df["status_ref_gene"][0] == "Mapped":
            truth_gene_seq = truth_and_ref_gene_df["sequence_truth_gene"][0]
            ref_gene_seq = truth_and_ref_gene_df["sequence_ref_gene"][0]
            edit_distance = editdistance.eval(truth_gene_seq, ref_gene_seq) / max(len(truth_gene_seq), len(ref_gene_seq))
        else:
            edit_distance = -1

        truth_and_ref_gene_df["edit_distance"] = edit_distance
        truth_and_ref_gene_df.to_csv(output.edit_distance_between_genes_of_truth_assemblies_and_ref, index=False)
