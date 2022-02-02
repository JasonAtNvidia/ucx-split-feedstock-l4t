#!/bin/bash
# Copyright (c) 2020, NVIDIA CORPORATION.
#######################################
# ucx-py conda build script for gpuCI #
#######################################
set -ex

# Set paths
export PATH=/opt/conda/bin:$PATH
export HOME=/home/conda

# Activate base conda env (this is run in docker condaforge/linux-anvil-cuda:CUDA_VER)
source activate base

# Print current env vars
env

# Install gpuCI tools
curl -s https://raw.githubusercontent.com/rapidsai/gpuci-mgmt/main/gpuci-tools.sh | bash
source ~/.bashrc
cd ~

# Copy workspace to home
gpuci_logger "Copy workspace from volume to home for work..."
cp -rT $WORKSPACE ~

# Get arch
ARCH="$(arch)"
if [ "$ARCH" = "x86_64" ]; then
  CONDA_ARCH="linux_64"
elif [ "${ARCH}" = "aarch64" ]; then
  CONDA_ARCH="linux_aarch64"
  sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-Linux-* \
    && sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Linux-* 
else
  echo "Unsupported arch ${ARCH}"
  exit 1
fi

# Install yum reqs
gpuci_logger "Install system libraries needed for build..."
xargs yum -y install < recipe/yum_requirements.txt

# Fetch pkgs for build
gpuci_logger "Install conda pkgs needed for build..."
# Previous versions of conda-build cause a build error. See https://github.com/conda-forge/conda-build-feedstock/pull/169
MORE_PKGS="conda-build>=3.21.6"
if [ "$CUDA_VER" != "None" ] ; then
  MORE_PKGS="${MORE_PKGS} cudatoolkit=${CUDA_VER}"
fi

conda install -y -k -c nvidia -c conda-forge -c defaults conda-verify ${MORE_PKGS}

# Print diagnostic information
gpuci_logger "Print conda info..."
conda info
conda config --show-sources
conda list --show-channel-urls

# Add settings for current CUDA version
cat ".ci_support/${CONDA_ARCH}_cuda_compiler_version${CUDA_VER}.yaml" > recipe/conda_build_config.yaml

# Allow insecure files to work with out conda mirror/proxy
echo "ssl_verify: false" >> /opt/conda/.condarc

# Print current env vars
gpuci_logger "Print current environment..."
env

# Start conda build
gpuci_logger "Starting conda build..."
conda build --override-channels -c conda-forge -c nvidia -c rapidsai-nightly .

# Get conda build output
gpuci_logger "Getting conda build output..."
conda build --override-channels -c conda-forge -c nvidia -c rapidsai-nightly . --output > conda.output

# Uploda files to anaconda
if [ ! -z "${MY_UPLOAD_KEY}" ] ; then
  gpuci_logger "Upload token present, uploading..."
  cat conda.output | xargs gpuci_retry anaconda -t ${MY_UPLOAD_KEY} upload -u ${CONDA_USERNAME:-rapidsai} --label main --skip-existing
else
  gpuci_logger "Upload token 'MY_UPLOAD_KEY' not present, skipping upload..."
fi
