import subprocess
import re
import csv
import os
import sys
import shutil

TOTAL_INSTRUCTIONS = 29499869.0

traceSize = 10

# 1792835

rePattern = r"Result:[\s]+[\d]+,[\s]+[\d]+"
RESULT_FILE = 'results.csv'

BI_LEN_MAX = 7

PHR_LENGTHS = [16, 32, 64]
GHR_SETS = [
    [5, 15, 44, 130],
    [5, 20, 80, 200]
]

TRACE_SRC = './trace_sources/'
TRACE_DST = './trace_files/'
TRACES = [
            ('DIST-INT-1', 10),
            ('DIST-INT-3', 5),
         ]

HEADERS = ['Trace', 'PHR', 'GHR 1', 'GHR 2', 'GHR 3', 'GHR 4', 'Individual Table Size', 'Accuracy',
           'MPKI', 'Correct', 'Incorrect']


def checkRoot():
    euid = os.geteuid()
    if euid != 0:
        print("Script not started as root. Running sudo..")
        args = ['sudo', sys.executable] + sys.argv + [os.environ]
        # the next line replaces the currently-running process with the sudo
        os.execlpe('sudo', *args)

    print('Running. Your euid is', euid)


if __name__ == '__main__':

    shutdown = (len(sys.argv) > 1) and sys.argv[1] == '-h'
    if shutdown:
        checkRoot()

    while os.path.exists(RESULT_FILE):
        print("Moving previous results")
        try:
            try:
                os.remove(f'{RESULT_FILE}.old')
            except Exception as e:
                print(e)
            os.rename(RESULT_FILE, f'{RESULT_FILE}.old')
        except Exception as e:
            print('Could not remove old results file:', e, "Retrying...")

    print("Starting simulations".center(50, "="))

    with open(RESULT_FILE, 'a') as csvFile:
        writer = csv.writer(csvFile, delimiter=',')
        writer.writerow(HEADERS)
        for trace in TRACES:

            shutil.copy(TRACE_SRC + trace[0] + "/traces_br.hex", TRACE_DST + "/traces_br.hex")
            shutil.copy(TRACE_SRC + trace[0] + "/traces_outcome.hex", TRACE_DST + "/traces_outcome.hex")
            
            for phr in PHR_LENGTHS:
                for ghrs in GHR_SETS:
                    for biLen in range(5, BI_LEN_MAX):
                        with open('parameterTemp.txt', 'r') as tempFile:
                            tableSize = pow(2, biLen)
                            template = tempFile.read().strip()
                            ghr1, ghr2, ghr3, ghr4 = ghrs
                            params = template.format(tableSize=tableSize, bimodalSize=tableSize,
                                                    bimodalLen=biLen, tableLen=biLen, ghr1=ghr1,
                                                    ghr2=ghr2, ghr3=ghr3, ghr4=ghr4, phrLen=phr,
                                                    traceSize=trace[1])

                            outFile = f'src/parameter.bsv'
                            with open(outFile, 'w') as f:
                                f.write(params)

                            res = subprocess.check_output(['make', 'all_bsim'])
                            res = res.decode('utf8')

                            matches = re.search(rePattern, res)
                            resultsStr = matches.group(0)
                            resultsStr = resultsStr.replace('Result:', '')
                            correct, incorrect = [int(x.strip())
                                                for x in resultsStr.split(",")]
                            print('correct', correct, 'incorrect', incorrect)

                            acc = correct * 100.0 / (correct + incorrect)
                            mpki = incorrect * 1000.0 / TOTAL_INSTRUCTIONS
                            row = [trace, phr] + ghrs + [tableSize, acc, mpki,
                                                correct, incorrect]
                            writer.writerow(row)

    subprocess.Popen(['xdg-open', 'results.csv'])

    if shutdown:
        subprocess.call(['chmod', '-R', '777', './'])
        print('Shutting Down...')
        os.system("shutdown -h now")
