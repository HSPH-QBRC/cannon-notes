workflow myWorkflow {

    String fname

    call printSum {
        input:
            output_file = fname
    }

    output {
        File output = printSum.out
    }
}


task printSum {
        
    String output_file

    command <<<
        python3 -c "print(2+2)" >${output_file}
    >>>

    output {
        File out = "${output_file}"
    }

    runtime {
        docker: "python"
        cpus: 1
        runtime_minutes: 10
        requested_memory_mb_per_core: 500
    }
}
