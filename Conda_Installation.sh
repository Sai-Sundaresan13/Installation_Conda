#!/usr/bin/env bash
###############################################################################
# Bioinformatics Environment Setup (Conda)
#
# Consolidates Installation_Conda/codes.txt:
#   - System update
#   - Miniconda installation
#   - Bioconda/conda-forge channel setup
#   - RNA-seq environment + tools (fastqc, multiqc, STAR, featureCounts, ...)
#
# Also adds commonly used bioinformatics tools as easy on/off toggles below.
# NOTE: hisat2 and samtools are included in CORE_TOOLS because your
# DESEQ_Analysis pipeline.sh needs them for the Alignment step, but the
# original codes.txt never installed them.
#
# Usage:
#   chmod +x install_env.sh
#   ./install_env.sh
#
# Everything installed here only works with the env activated:
#   conda activate rnaseq
###############################################################################

set -euo pipefail

# ============================== CONFIG ======================================
ENV_NAME="rnaseq"
PYTHON_VERSION="3.10"

MINICONDA_INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
MINICONDA_URL="https://repo.anaconda.com/miniconda/${MINICONDA_INSTALLER}"

# --- Core tools from the original repo (RNA-seq preprocessing pipeline) -----
CORE_TOOLS=(
    fastqc
    multiqc
    trim-galore
    star
    hisat2          
    samtools        
    subread         
)

# --- Commonly used extra bioinformatics tools (toggle true/false) ----------
INSTALL_SRA_TOOLS=true     # prefetch / fasterq-dump, for pulling data from SRA/ENA
INSTALL_CUTADAPT=true      # adapter trimming (also a Trim Galore dependency)
INSTALL_BOWTIE2=true       # alternative short-read aligner
INSTALL_SALMON=true        # fast alignment-free transcript quantification
INSTALL_STRINGTIE=true     # transcript assembly / quantification
INSTALL_BEDTOOLS=true      # genomic interval arithmetic
INSTALL_BCFTOOLS=true      # VCF/BCF manipulation
INSTALL_DEEPTOOLS=true     # BAM/bigWig coverage tools, useful for visualization
INSTALL_QUALIMAP=true      # BAM/alignment QC reports
INSTALL_RSEQC=true         # RNA-seq specific QC (read distribution, gene body coverage)
INSTALL_SEQKIT=true        # fast FASTA/FASTQ manipulation and stats
INSTALL_GATK4=false        # variant calling toolkit (heavy install, off by default)
INSTALL_MULTIQC_PLUGINS=false
# =============================================================================

log() { echo -e "\n>>> $*\n"; }

# Common install locations to check if `conda` isn't already on PATH.
# This matters because each run of this script is a fresh shell process:
# `conda init` edits ~/.bashrc, but ~/.bashrc is only auto-sourced by
# *interactive* shells, not by a script being executed. So we resolve
# conda's location from disk directly instead of assuming PATH is set.
CONDA_BASE_CANDIDATES=(
    "$HOME/miniconda3"
    "$HOME/anaconda3"
    "/opt/conda"
    "/opt/miniconda3"
)

# Try to make `conda` usable in the current process. Returns 1 (no exit)
# if it can't be found, so callers can decide whether that's fatal.
try_source_conda() {
    if command -v conda >/dev/null 2>&1; then
        return 0
    fi
    for base in "${CONDA_BASE_CANDIDATES[@]}"; do
        if [ -f "$base/etc/profile.d/conda.sh" ]; then
            # shellcheck disable=SC1091,SC1090
            source "$base/etc/profile.d/conda.sh"
            return 0
        fi
    done
    return 1
}

require_conda() {
    try_source_conda || {
        echo "ERROR: could not find conda (checked PATH and: ${CONDA_BASE_CANDIDATES[*]})." >&2
        echo "Run './install_env.sh miniconda' first, or install conda manually." >&2
        exit 1
    }
}

# ---- Step 1: System update ---------------------------------------------------
step_update_system() {
    log "Step 1: Updating system packages"
    sudo apt update
    sudo apt upgrade -y
}

# ---- Step 2: Install Miniconda ----------------------------------------------
step_install_miniconda() {
    if try_source_conda; then
        log "Step 2: conda already installed, skipping Miniconda install"
        return
    fi
    log "Step 2: Installing Miniconda"
    wget -q "$MINICONDA_URL" -O "$MINICONDA_INSTALLER"
    bash "$MINICONDA_INSTALLER" -b -p "$HOME/miniconda3"
    rm -f "$MINICONDA_INSTALLER"

    # shellcheck disable=SC1091
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda init bash
    echo "Miniconda installed and sourced for this session."
    echo "(Open a new terminal, or 'source ~/.bashrc', for 'conda' to work in interactive shells too.)"
}

# ---- Step 2b: Accept Anaconda Terms of Service ------------------------------
# Newer conda versions refuse to solve/create envs against the 'defaults'
# channels non-interactively until ToS is accepted. Safe no-op on older
# conda versions that don't have this requirement.
step_accept_tos() {
    require_conda
    log "Step 2b: Accepting Terms of Service for default Anaconda channels"
    if conda tos --help >/dev/null 2>&1; then
        conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
        conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
    else
        echo "This conda version doesn't require explicit ToS acceptance, skipping."
    fi
}

# ---- Step 3: Configure channels ---------------------------------------------
step_configure_channels() {
    require_conda
    log "Step 3: Configuring conda channels (defaults, bioconda, conda-forge)"
    conda config --add channels defaults
    conda config --add channels bioconda
    conda config --add channels conda-forge
    conda config --set channel_priority strict
}

# ---- Step 4: Create environment ---------------------------------------------
step_create_env() {
    require_conda
    log "Step 4: Creating conda environment '$ENV_NAME'"
    if conda env list | grep -qE "^\s*${ENV_NAME}\s"; then
        echo "Environment '$ENV_NAME' already exists, skipping creation."
    else
        conda create -n "$ENV_NAME" -y python="$PYTHON_VERSION"
    fi
}

# ---- Step 5: Install core tools ---------------------------------------------
step_install_core_tools() {
    require_conda
    log "Step 5: Installing core tools into '$ENV_NAME': ${CORE_TOOLS[*]}"
    conda install -n "$ENV_NAME" -c conda-forge -c bioconda -y "${CORE_TOOLS[@]}"
}

# ---- Step 6: Install optional/extra tools -----------------------------------
step_install_extra_tools() {
    require_conda
    log "Step 6: Installing additional commonly used tools"
    local extras=()

    $INSTALL_SRA_TOOLS && extras+=(sra-tools)
    $INSTALL_CUTADAPT  && extras+=(cutadapt)
    $INSTALL_BOWTIE2   && extras+=(bowtie2)
    $INSTALL_SALMON    && extras+=(salmon)
    $INSTALL_STRINGTIE && extras+=(stringtie)
    $INSTALL_BEDTOOLS  && extras+=(bedtools)
    $INSTALL_BCFTOOLS  && extras+=(bcftools)
    $INSTALL_DEEPTOOLS && extras+=(deeptools)
    $INSTALL_QUALIMAP  && extras+=(qualimap)
    $INSTALL_RSEQC     && extras+=(rseqc)
    $INSTALL_SEQKIT    && extras+=(seqkit)
    $INSTALL_GATK4     && extras+=(gatk4)

    if [ "${#extras[@]}" -eq 0 ]; then
        echo "No extra tools selected, skipping."
        return
    fi

    echo "Installing: ${extras[*]}"
    conda install -n "$ENV_NAME" -c conda-forge -c bioconda -y "${extras[@]}"
}

# ---- Step 7: Verify installation --------------------------------------------
step_verify() {
    require_conda
    log "Step 7: Verifying installed tool versions"
    conda activate "$ENV_NAME"

    for tool_cmd in "fastqc --version" "multiqc --version" "trim_galore --version" \
                    "STAR --version" "hisat2 --version" "samtools --version" \
                    "featureCounts -v"; do
        cmd="${tool_cmd%% *}"
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "--- $tool_cmd ---"
            $tool_cmd 2>&1 | head -n 2
        else
            echo "--- $cmd: not found ---"
        fi
    done
    conda deactivate
}

# ---- Driver ------------------------------------------------------------------
run_step() {
    case "$1" in
        update)       step_update_system ;;
        miniconda)    step_install_miniconda ;;
        tos)          step_accept_tos ;;
        channels)     step_configure_channels ;;
        env)          step_create_env ;;
        core)         step_install_core_tools ;;
        extra)        step_install_extra_tools ;;
        verify)       step_verify ;;
        all)
            step_update_system
            step_install_miniconda
            step_accept_tos
            step_configure_channels
            step_create_env
            step_install_core_tools
            step_install_extra_tools
            step_verify
            ;;
        *)
            echo "Unknown step: $1" >&2
            echo "Valid steps: update miniconda tos channels env core extra verify all" >&2
            exit 1
            ;;
    esac
}

main() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: $0 [all|update|miniconda|tos|channels|env|core|extra|verify] ..." >&2
        exit 1
    fi
    for step in "$@"; do
        run_step "$step"
    done
}

main "$@"
