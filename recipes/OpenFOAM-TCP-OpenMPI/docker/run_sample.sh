#!/usr/bin/env bash

set -e
set -o pipefail

# get mpi ref and set up openfoam env
OPENFOAM_DIR=/opt/OpenFOAM/OpenFOAM-v1606+
source /etc/profile.d/modules.sh
module add mpi/openmpi-x86_64
source $OPENFOAM_DIR/etc/bashrc

# copy sample into glusterfs shared area
GFS_DIR=$AZ_BATCH_NODE_SHARED_DIR/gfs
cd $GFS_DIR
cp -r $OPENFOAM_DIR/tutorials/incompressible/simpleFoam/pitzDaily .
cp $OPENFOAM_DIR/tutorials/incompressible/simpleFoam/pitzDailyExptInlet/system/decomposeParDict pitzDaily/system/

# get nodes and compute number of processors
IFS=',' read -ra HOSTS <<< "$AZ_BATCH_HOST_LIST"
nodes=${#HOSTS[@]}
ppn=`nproc`
np=$(($nodes * $ppn))

# substitute proper number of subdomains
sed -i -e "s/^numberOfSubdomains 4/numberOfSubdomains $np;/" pitzDaily/system/decomposeParDict

# decompose
cd pitzDaily
blockMesh
decomposePar -force

# create hostfile
touch hostfile
>| hostfile
for node in "${HOSTS[@]}"
do
    echo $node slots=$ppn max-slots=$ppn >> hostfile
done

# execute mpi job
mpirun=`which mpirun`
mpienvopts=`echo \`env | grep WM_ | sed -e "s/=.*$//"\` | sed -e "s/ / -x /g"`
mpienvopts2=`echo \`env | grep FOAM_ | sed -e "s/=.*$//"\` | sed -e "s/ / -x /g"`
$mpirun --allow-run-as-root --mca btl_tcp_if_exclude docker0 -np $np --hostfile hostfile -x PATH -x LD_LIBRARY_PATH -x MPI_BUFFER_SIZE -x $mpienvopts -x $mpienvopts2 simpleFoam -parallel