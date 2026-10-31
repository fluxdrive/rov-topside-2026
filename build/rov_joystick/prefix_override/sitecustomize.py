import sys
if sys.prefix == '/home/robosub/Downloads/rov-topside-2026-main-robostack/.pixi/envs/default':
    sys.real_prefix = sys.prefix
    sys.prefix = sys.exec_prefix = '/home/robosub/Downloads/rov-topside-2026-main-robostack/install/rov_joystick'
