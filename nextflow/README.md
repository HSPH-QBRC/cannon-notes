# Notes/instructions for use of Nextflow on FASRC Cannon

This document covers basic instructions for executing Nextflow-based processes on the Cannon cluster. We assume familiarity with Nextflow in general, and cover specific styles of workflows with basic examples


## Setup

- Log in to the cluster and start an interactive session (e.g. `salloc -p hsph --mem 8000 -c1 -t 0-01:00`)
- Download the Nextflow application using instructions at https://www.nextflow.io/docs/latest/install.html . 
  - At the date of writing, this amounts to running:
    - `curl -s https://get.nextflow.io | bash` 
    - `chmod +x nextflow`
    - (optional) Relocate `nextflow` to a final location on your `$PATH` (or some other memorable personal location), or in a common group/lab space. The idea of this second option is that one can install the Nextflow application and permit execution by all members of the group instead of maintaining personal copies.
- Test the installation with:
```
module load jdk/20.0.1-fasrc01
nextflow info
```
Note that the default Java runtime available on Cannon will likely raise an exception. Above, we load a more recent Java available through Cannon's modules. The specific version might change over time, so be aware of that. 

In the output above, you should see something like:
```
nextflow info
  Version: 23.04.4 build 5881
  Created: 25-09-2023 15:34 UTC (11:34 EDT)
  System: Linux 4.18.0-513.18.1.el8_9.x86_64
  Runtime: Groovy 3.0.16 on Java HotSpot(TM) 64-Bit Server VM 20.0.1+9-29
  Encoding: UTF-8 (UTF-8)

```

### Create some dummy script to run in the Nextflow process

Here, we create a Python script which creates a CSV-format file of random integers. It expects a filename (which specifies the output file name) as the only argument. It requires the numpy and pandas packages, which are not included in the default system python, so our process will need to use either containers or Conda environments to run this.

```python
import sys

import numpy as np
import pandas as pd

X = pd.DataFrame(
    {
        'x': np.random.randint(0,100,size=10),
        'y': np.random.randint(0,100,size=10)
})

X.to_csv(sys.argv[1], index=False)
```
e.g. you would typically run this with 
```
<path to python3>/bin/python3 <PATH TO SCRIPT DIR>/example.py foo.csv
```
Save this script in a memorable location on Cannon. Above, mock out the actual path and used `<PATH TO SCRIPT DIR>/example.py` which is used below in the Nextflow scripts. Obviously replace with the actual path in all these instances.

## Using container-based tools

If your tool or application is already distributed in a Docker or Singularity container, then you can direct Nextflow tasks to use these as the execution context. Note that since Docker is not permitted on Cannon, Nextflow will automatically perform a conversion to Singularity format.  

In the process below, we specify a public Docker image hosted by GitHub's container registry. This Docker image has numpy and pandas installed, which are required for our Python script above.

Nextflow script `basic.nf`:
```
process make_random_mtx {

    publishDir "${params.output_dir}/results/", mode: "copy"
    container "ghcr.io/web-mev/pca:sha-4a9b9e76b7ac03793184ccf3d1b27f08c51341a7"
    cpus 1
    memory '6 GB'

    input:
        val filename

    output:
        path "${filename}"

    script:
        """
        /opt/conda/bin/python3 <PATH TO SCRIPT DIR>/example.py ${filename}
        """
}

workflow {
    make_random_mtx(params.fname)
}
```
Note the following:
- the `container` directive, which specifies a Docker image (e.g. Dockerhub, GitHub container repo, etc.)
  - Even though this was a Docker container above, the conversion to Cannon-compatible Singularity image format (`sif`) will happen automatically. This conversion will be printed to the logs.
- Inside the `script` block, we use the python version packaged in the Docker container. Here, that is `/opt/conda/bin/python3`, but would obviously change for your particular container. 
- Despite the fact we are using a container, the path to the script is the path on Cannon- Nextflow handles the filesystem mount to the container.

To run this on Cannon, we need a parameters input file where we specify the name of the output file and the location. For example:

`params.json`:
```
{
    "fname": "foo.tsv",
    "output_dir": "<PATH TO RESULTS>/demo_output"
}
```
Additionally, we need to tell Nextflow that we are in a SLURM-based system and wish to use containers. To do this, we can supply a config file:

`nextflow.config`:
```
process.executor = 'slurm'
singularity.enabled = true
```

## Using Conda-based tools

If you have a Conda environment already built on Cannon, you can point your Nextflow process to that. For instance, if you have the following environment file:

`env.yaml`
```
name: myenv
channels:
  - conda-forge
dependencies:
  - numpy
  - pandas
```
You can build this on Cannon with:
```
module load Mambaforge
mamba env create -f env.yaml --prefix=<PATH TO ENV>
```
This will locate the environment at `<PATH TO ENV>`, which could be in a common lab directory for re-use.

In the nextflow script below, we will direct Nextflow to make use of that Conda environment:

`basic.nf`:
```
process make_random_mtx {

    conda '<PATH TO ENV>'

    publishDir "${params.output_dir}/results/", mode: "copy"
    cpus 1
    memory '4 GB'

    input:
        val filename

    output:
        path "${filename}"

    script:
        """
        <PATH TO ENV>/bin/python3 <PATH TO SCRIPT DIR>/example.py ${filename}
        """
}

workflow {
    make_random_mtx(params.infile)
}
```
Note that the script above does the same as with the container-based run, except that we use the `conda` directive and alter the path to Python in the `script` block.

We have the same input parameters, so that doesn't change (see the example `params.json` above)

Since we are not using containers, our Nextflow config only needs to specify that we are on a SLURM system:

`nextflow.config`:
```
process.executor = 'slurm'
```

## Submitting jobs
Finally, regardless of whether we are using container- or conda-based runs, we can submit using a script like the following:

`submit.sh`:
```
#!/bin/bash

# Obviously change these to match your job requirements:
#SBATCH -c 2                # Number of cores (-c)
#SBATCH -t 0-1:00           # Runtime in D-HH:MM, minimum of 10 minutes
#SBATCH -p hsph             # Partition to submit to
#SBATCH --mem=2000          # Memory pool for all cores (see also --mem-per-cpu)
#SBATCH -o output_%j.out    # File to which STDOUT will be written, %j inserts jobid
#SBATCH -e errors_%j.err    # File to which STDERR will be written, %j inserts jobid

# load a recent JDK- could change over time, so check RC docs
module load jdk/20.0.1-fasrc01

# initial and maximum memory for JVM
export NXF_OPTS="-Xms1000M -Xmx2G"

# change to the working directory
cd <YOUR DIRECTORY WITH NEXTFLOW SCRIPTS, ETC.>
<PATH TO NEXTFLOW BIN>/nextflow run basic.nf -params-file params.json -c nextflow.config
```
e.g. submit with `sbatch submit.sh`.

Upon completion, of the process, you should have a CSV-format file in the `results` directory, which is itself inside the output directory you specified in your `params.json`. 

## Potential pitfalls

- Memory specifications: If the `submit.sh` script above does not have sufficient memory to perform the Docker to Singularity conversion, you can get situations where the job is killed due to out-of-memory issues. Adjust as necessary.