// Forked from SetProtocol, to assist with contract verifications. Ty.
// https://github.com/SetProtocol/index-deployments/blob/master/tasks/compileOne.ts

import { task } from "hardhat/config";
import {
  TASK_COMPILE_SOLIDITY_GET_COMPILATION_JOB_FOR_FILE,
  TASK_COMPILE_SOLIDITY_GET_DEPENDENCY_GRAPH,
  TASK_COMPILE_SOLIDITY_COMPILE_JOB,
} from "hardhat/builtin-tasks/task-names";

import * as taskTypes from "hardhat/types/builtin-tasks";

task("compile:one", "Compiles a single contract in isolation")
  .addPositionalParam("contractName")
  .setAction(async function (args, env) {
    const sourceName = env.artifacts.readArtifactSync(args.contractName).sourceName;

    const dependencyGraph: taskTypes.DependencyGraph = await env.run(TASK_COMPILE_SOLIDITY_GET_DEPENDENCY_GRAPH, {
      sourceNames: [sourceName],
    });

    const resolvedFiles = dependencyGraph.getResolvedFiles().filter((resolvedFile) => {
      return resolvedFile.sourceName === sourceName;
    });

    const compilationJob: taskTypes.CompilationJob = await env.run(TASK_COMPILE_SOLIDITY_GET_COMPILATION_JOB_FOR_FILE, {
      dependencyGraph,
      file: resolvedFiles[0],
    });

    await env.run(TASK_COMPILE_SOLIDITY_COMPILE_JOB, {
      compilationJob,
      compilationJobs: [compilationJob],
      compilationJobIndex: 0,
      emitsArtifacts: true,
      quiet: true,
    });

    await env.run("typechain");
  });
