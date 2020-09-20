# CastANet - castanet.py

import os
# Disables tensorflow messages/warnings.
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

import castanet_train as cTrain
import castanet_config as cConfig
import castanet_predict as cPredict



def main():

    cConfig.initialize()
    run_mode = cConfig.get('run_mode')
    input_files = cConfig.get_input_files()

    if run_mode == 'train':

        cTrain.run(input_files)

    elif run_mode == 'predict':

        cPredict.run(input_files)

    else:

        pass



if __name__ == '__main__':

    main()
