import fs from 'fs';

// Read the test output
const output = fs.readFileSync('/var/folders/8y/3l9zkh1d5kdff33h14vbffxc0000gn/T/claude/-Users-karim-Documents-workspace-zero-trust-e-tour/tasks/b2f89a1.output', 'utf-8');

const lines = output.split('\n');
const structure = [];
let currentSuite = null;
let currentSubsuite = null;

for (let line of lines) {
    // Main test suite (no indentation)
    if (line.match(/^  \S/) && !line.includes('✔') && !line.includes('○') && !line.includes('passing') && !line.includes('pending')) {
        currentSuite = {
            name: line.trim(),
            subsuites: [],
            tests: []
        };
        structure.push(currentSuite);
        currentSubsuite = null;
    }
    // Sub-suite (4 spaces indentation)
    else if (line.match(/^    \S/) && !line.includes('✔') && !line.includes('○')) {
        if (currentSuite) {
            currentSubsuite = {
                name: line.trim(),
                tests: []
            };
            currentSuite.subsuites.push(currentSubsuite);
        }
    }
    // Test case (with checkmark or circle)
    else if (line.includes('✔') || line.includes('○')) {
        const testName = line.replace(/[✔○]/, '').trim().replace(/\(\d+ms\)/, '').trim();
        const isPending = line.includes('○');
        const test = {
            name: testName,
            status: isPending ? 'pending' : 'passing'
        };

        if (currentSubsuite) {
            currentSubsuite.tests.push(test);
        } else if (currentSuite) {
            currentSuite.tests.push(test);
        }
    }
}

// Count statistics
let totalPassing = 0;
let totalPending = 0;

for (let suite of structure) {
    let suitePassing = 0;
    let suitePending = 0;

    for (let test of suite.tests) {
        if (test.status === 'passing') suitePassing++;
        else suitePending++;
    }

    for (let subsuite of suite.subsuites) {
        for (let test of subsuite.tests) {
            if (test.status === 'passing') suitePassing++;
            else suitePending++;
        }
    }

    suite.passing = suitePassing;
    suite.pending = suitePending;
    totalPassing += suitePassing;
    totalPending += suitePending;
}

const result = {
    totalPassing,
    totalPending,
    totalTests: totalPassing + totalPending,
    successRate: ((totalPassing / (totalPassing + totalPending)) * 100).toFixed(1),
    suites: structure
};

console.log(JSON.stringify(result, null, 2));
