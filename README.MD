RUN ORDER (Kali):
1) bash setup_kali_fabric.sh
   (then open a new terminal or: source ~/.bashrc ; newgrp docker)

2) bash scripts/start_testnet.sh
3) bash scripts/add_org3.sh
4) bash scripts/create_mfg_dist.sh
5) bash scripts/deploy_cc_global.sh
6) bash scripts/deploy_cc_mfgdist.sh
7) bash scripts/demo_flow.sh
