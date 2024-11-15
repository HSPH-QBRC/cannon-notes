# Notes on working with Cromwell on Cannon

## Context

If you have WDL-defined workflows/pipelines, we can use Cromwell to execute these on Cannon. This document describes how to do this all. Often, Cromwell is run as a server with an API. However,
here we are only concerned with running workflows directly and *not* making use of Cromwell's server capabilities.

## Cromwell information

https://github.com/broadinstitute/cromwell

https://cromwell.readthedocs.io/en/latest/

## Basic setup- local runner

Note that Cromwell can run its tasks locally (using software installed on the host system), or it can execute tasks using software installed in containers (Singularity in the case of Cannon). 
For this section, we are setting up a basic local runner. To use containers on Cannon, you will need additional configuration, detailed further below.

You can download a JAR of the latest release from the Cromwell github pages (https://github.com/broadinstitute/cromwell/releases). Download this to a location on Cannon (e.g. lab home folder).

To execute the JAR, you need to load an appropriate JDK module on Cannon. Use `module spider jdk` to see the latest. For example,

```
module load jdk/22.0.2-fasrc01
```

Next, test that it works by running this basic Hello, world!:

### `hello_world.wdl`
```
workflow myWorkflow {
    call myTask
}

task myTask {
    command <<<
        echo "hello world"
    >>>
    output {
        String out = read_string(stdout())
    }
}
```

with the following:

```
java -jar /path/to/cromwell-XY.jar run hello_world.wdl
```

Hopefully this executes without an error. Note that this simply uses the host node and does not make any submissions to slurm.

## More advanced setup- using Singularity containers

If you are running a workflow that depends on containers, you need to include an additional configuration file when you run Cromwell. The config instructs Cromwell on how to interact
with the containers and how to start/stop/monitor tasks on the job scheduler. Since Cannon uses slurm, our configuration has to include slurm + singularity functionality.

With pre-configured workflows (such as those distributed by Broad), they can often include premade Docker containers hosted on Dockerhub. Cannon will not run Docker containers due to 
security concerns, but the configuration below *will* pull these Docker images and create `.sif` Singularity image files for use. All this can be seen in `fasrc.conf`

To run workflows on Cannon, copy this config file and refer to it when running the JAR:
```
java -Dconfig.file=/path/to/fasrc.conf -jar /path/to/cromwell-XY.jar run myWorkflow.wdl
```

For example, you can copy and run the example from `docker_example.wdl` which performs the calculation of 2+2 using the Python Docker image. To run this, you also need to create an inputs JSON
file which allows you to customize the name of the output file. For example,

```
{
  "myWorkflow.fname": "output_file.txt"
}
```

then run:
```
java -Dconfig.file=/path/to/fasrc.conf -jar /path/to/cromwell-XY.jar run docker_example.wdl --inputs input_params.json
```

## Addition notes for WDL

This document is not about WDL specifically, but there are some WDL-related changes for working properly with slurm. Namely, in the `runtime` stanza, you dictate
the task requirements with the following (which is controlled in the config file above)

```
  runtime {
      docker: "<Docker Image URI>"
      cpus: <int>
      runtime_minutes: <int>
      requested_memory_mb_per_core: <int>
  }
```
Again, even though it says `docker`, the configuration above will perform the conversion to Singularity SIF images.
