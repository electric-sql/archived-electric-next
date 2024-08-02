import { spawn, spawnSync } from 'child_process';
 
const ELECTRIC_URL=process.env.ELECTRIC_URL ?? 'http://localhost:3000'
const TIME=process.env.TIME ?? '1m'
const OUTPUT_DIR=process.env.OUTPUT_DIR

async function runTest(name){
    // load json from file
    const config = await import(`./tests/configurations/${name}.json`, {
        assert: { type: 'json' }
      });
    
    for (let i = 0; i < config.default.length; i++){
        runConfig(name, config.default[i], i);
    }
}

function runConfig(name, config, configIndex){
    const args = [
        '-H', ELECTRIC_URL,
        '-t', TIME,
        '--autostart',
        '--autoquit', '0',
        '-u', config.users,
        '-r', config.rate,
        '-f', `tests/${name}.py`,
        '--config-users', `${JSON.stringify(config.config)}`
    ];

    if (OUTPUT_DIR){
        const output = `${OUTPUT_DIR}/${name}-${config.users}-${config.rate}-${configIndex}`;
        args.push('--csv');
        args.push(output);
        args.push(`--csv-full-history`);
    }

    console.log(`Running locust with args: ${args}`);
    spawnSync('locust', args, { stdio: 'inherit'});
}

const args = process.argv.slice(2);

const testname = args[0];
await runTest(testname);

