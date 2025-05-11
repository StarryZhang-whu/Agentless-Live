set -ex

model=${1:-gpt-4.1-20250414}
dataset=${2:-test.jsonl}
localize_samples=${3:-1}
repair_samples=${4:-1}
num_threads=${5:-10}

outdir="results/${model}"

echo "Args:"
echo "  Model: $model"
echo "  Dataset: $dataset"
echo "  Localize samples: $localize_samples"
echo "  Repair samples: $repair_samples"
echo "  Output dir: $outdir"
echo

# 1.1
date "+%Y-%m-%d %H:%M:%S"
python agentless/fl/localize.py \
    --file_level \
    --output_folder $outdir/file_level \
    --num_threads $num_threads \
    --dataset $dataset \
    --model $model \
    --skip_existing

# 1.2
date "+%Y-%m-%d %H:%M:%S"
python agentless/fl/localize.py \
    --file_level \
    --irrelevant \
    --output_folder $outdir/file_level_irrelevant \
    --num_threads $num_threads \
    --dataset $dataset \
    --model $model \
    --skip_existing

# 1.3
date "+%Y-%m-%d %H:%M:%S"
python agentless/fl/retrieve.py \
    --index_type simple \
    --filter_type given_files \
    --filter_file $outdir/file_level_irrelevant/loc_outputs.jsonl \
    --output_folder $outdir/retrievel_embedding \
    --persist_dir embedding \
    --num_threads $num_threads \
    --dataset $dataset

# 1.4
date "+%Y-%m-%d %H:%M:%S"
python agentless/fl/combine.py \
    --retrieval_loc_file $outdir/retrievel_embedding/retrieve_locs.jsonl \
    --model_loc_file $outdir/file_level/loc_outputs.jsonl \
    --top_n 3 \
    --output_folder $outdir/file_level_combined

# 2.1
date "+%Y-%m-%d %H:%M:%S"
python agentless/fl/localize.py \
    --related_level \
    --output_folder $outdir/related_elements \
    --top_n 3 \
    --compress_assign \
    --compress \
    --start_file $outdir/file_level_combined/combined_locs.jsonl \
    --num_threads $num_threads \
    --dataset $dataset \
    --model $model \
    --skip_existing

# 3.1
date "+%Y-%m-%d %H:%M:%S"
python agentless/fl/localize.py \
    --fine_grain_line_level \
    --output_folder $outdir/edit_location_samples \
    --top_n 3 \
    --compress \
    --temperature 0.8 \
    --num_samples $localize_samples \
    --start_file $outdir/related_elements/loc_outputs.jsonl \
    --num_threads $num_threads \
    --dataset $dataset \
    --model $model \
    --skip_existing

# 3.2
date "+%Y-%m-%d %H:%M:%S"
python agentless/fl/localize.py \
    --merge \
    --output_folder $outdir/edit_location_individual \
    --top_n 3 \
    --num_samples $localize_samples \
    --start_file $outdir/edit_location_samples/loc_outputs.jsonl \
    --dataset $dataset \
    --model $model

# repair
date "+%Y-%m-%d %H:%M:%S"
for i in `seq 1 ${localize_samples}`; do
    ii=$(($i - 1))
    python agentless/repair/repair.py \
        --loc_file $outdir/edit_location_individual/loc_merged_${ii}-${ii}_outputs.jsonl \
        --output_folder $outdir/repair_sample_${i} \
        --loc_interval \
        --top_n 3 \
        --context_window 10 \
        --max_samples ${repair_samples} \
        --cot \
        --diff_format \
        --gen_and_process \
        --dataset $dataset \
        --num_threads $num_threads \
        --model $model
done
