import { spawn } from 'child_process';

const DATABASE_URL=process.env.DATABASE_URL

if(!DATABASE_URL){
    console.error('DATABASE_URL is not set');
    process.exit(1);
}

function spawn_psql(args){
  args = [
    DATABASE_URL,
    ...args
  ];
  console.log(`Running psql with args: ${args}`);
  const child = spawn('psql', args);
    
    // Listen for output from the command
    child.stdout.on('data', (data) => {
      console.log(`stdout: ${data}`);
    });
    
    // Listen for errors from the command
    child.stderr.on('data', (data) => {
      console.error(`stderr: ${data}`);
    });
}

function loadData(tablename, filename){
    const args = [
      '-c', `\\copy ${tablename} FROM ${filename}`,
    ];
    spawn_psql(args);
}

function dumpData(tablename, filename){
  console.log(`Dumping data from ${tablename} to ${filename}`);
  const args = [
    '-c', `\\copy ${tablename} TO ${filename}`,
  ];
  spawn_psql(args);
}

function script(filename){
  console.log(`Running script: ${filename}`);
  const args = [
    '-f', filename,
  ];
  spawn_psql(args);
}

const args = process.argv.slice(2);

const cmd = args[0];
const tablename = args[1];
const filename = args[2];
const sql = args[1];

switch(cmd){
  case 'dump':
    if(!tablename || !filename){
      console.error(`usage: dump-data 'tablename' 'filename'`);
      process.exit(1);
    }
    dumpData(tablename, filename);
    break;
  case 'load':
    if(!tablename || !filename){
      console.error(`usage: load-data 'tablename' 'filename'`);
      process.exit(1);
    }
    loadData(tablename, filename);
    break;
  case 'script':
    if(!script){
      console.error(`usage: script 'filename'`);
      process.exit(1);
    }
    script(sql);
    break;
}
