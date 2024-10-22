
def run(
    plan,
    args={}
):

    #####
    # StarGaze
    #####

    plan.print("Stargaze service")
    # Service name
    service_name="stargaze-local"

    # Custom Entrypoint
    data_path = "./entry-point.sh"

    # Deploy contract list
    contracts_list= [
        "cw721_base",
        # "hpl_mailbox",
        # "hpl_validator_announce",
        # "hpl_ism_aggregate",
        # "hpl_ism_multisig",
        # "hpl_ism_pausable",
        # "hpl_ism_routing",
        # "hpl_igp",
        # "hpl_hook_aggregate",
        # "hpl_hook_fee",
        # "hpl_hook_merkle",
        # "hpl_hook_pausable",
        # "hpl_hook_routing",
        # "hpl_hook_routing_custom",
        # "hpl_hook_routing_fallback",
        # "hpl_test_mock_hook",
        # "hpl_test_mock_ism",
        # "hpl_test_mock_msg_receiver",
        # "hpl_igp_oracle",
        # "hpl_warp_cw20",
        # "hpl_warp_native"
    ]
    
    plan.print("Starting with the following configuration: " + str(args))

    # load entry-point file as a volume file
    data = plan.upload_files(
        src=data_path,
        name="data",
    )

    service_config=ServiceConfig(
        image="publicawesome/stargaze:14.0.0",
        # use the new entry-point.sh
        entrypoint = ["/data/entry-point.sh"],
        ports={ 
            "rpc": PortSpec(number=26657,transport_protocol="TCP",application_protocol="http"),
            "p2p": PortSpec(number=26656,transport_protocol="TCP",application_protocol="http"),
            "rest": PortSpec(number=1317,transport_protocol="TCP",application_protocol="http"),
        },
        public_ports={ 
            "rpc": PortSpec(number=args["public_rpc_port"], transport_protocol="TCP",application_protocol="http"),
            "p2p": PortSpec(number=args["public_p2p_port"],transport_protocol="TCP",application_protocol="http"),
            "rest": PortSpec(number=args["public_rest_port"],transport_protocol="TCP",application_protocol="http"),
        },
        env_vars = { 
            "DENOM": "ustars",
            "CHAINID": "testing",
            "GAS_LIMIT": "75000000",
        },
        files = {"/data": data},
    )

    stargaze = plan.add_service(name=service_name,config=service_config)

    cmd="apk add curl jq unzip"
    download_cw721 = plan.exec(
        description="Installing tools dependencies",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    # Download cw721 and hyperlane contracts
    cmd="curl -s -L -O https://github.com/public-awesome/cw-nfts/releases/download/v0.18.0/cw721_base.wasm"
    download_cw721 = plan.exec(
        description="Downloading cw721 base smart contract",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    cmd="curl -s -L -O https://github.com/many-things/cw-hyperlane/releases/download/v0.0.7-rc0/cw-hyperlane-v0.0.7-rc0.zip && unzip -q cw-hyperlane-v0.0.7-rc0.zip"
    download_cw721 = plan.exec(
        description="Downloading hyperlane smart contracts",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]
    
    contracts = {}

    # Create development account
    cmd = "echo \"{0}\" | starsd keys add dev01 --keyring-backend test --recover".format(args["dummy_mnemonic"])
    create_dev_wallet = plan.exec(
        description="Creating Development Account",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    cmd = "starsd keys list --keyring-backend test --output json | jq -r '[.[] | {(.name): .address}] | tostring | fromjson | reduce .[] as $item ({} ; . + $item)' | jq '.validator' | sed 's/\"//g;' | tr '\n' ' ' | tr -d ' '"
    validator_addr = plan.exec(
        description="Getting Validator Address",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    cmd = "starsd keys list --keyring-backend test --output json | jq -r '[.[] | {(.name): .address}] | tostring | fromjson | reduce .[] as $item ({} ; . + $item)' | jq '.dev01' | sed 's/\"//g;' | tr '\n' ' ' | tr -d ' '"
    dev_addr = plan.exec(
        description="Getting Dev Address",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    # kurtosis is so limited that we need to filter \n and to use that we need tr....
    cmd="starsd tx bank send {0} {1} 1000000000ustars --keyring-backend test --fees 75000ustars -y --output json 2> /dev/null | jq '.txhash' | sed 's/\"//g;' | tr '\n' ' ' | tr -d ' '".format(validator_addr,dev_addr)
    fund_wallet = plan.exec(
        description="Funding dev wallet {0}".format(dev_addr),
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    cmd="sleep 5 && starsd query bank balances {0}".format(dev_addr)
    fund_wallet = plan.exec(
        description="Checking dev wallet balance {0}".format(dev_addr),
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    # ---------------Deploy contracts


    for contract_name in contracts_list:
        contract_code_id=deploy_contracts(plan, contract_name, service_name)
        contracts.update({contract_name: { "code_id": contract_code_id, "addr": ""}})

    #https://github.com/public-awesome/cw-nfts/blob/a5abe476c1028b2563f995adab184b86e3fc03ff/packages/cw721/src/msg.rs#L126
    # be aware that format "strips" characters like \"
    cw721_init='{\"name\":\"TestNFT\",\"symbol\":\"LazyNFT\",\"minter\":\"' +"{0}".format(dev_addr)+'\"}'
    cw721_id= contracts["cw721_base"]["code_id"]

    # starsd tx wasm instantiate 1 '{"name":"TestNFT","symbol":"LazyNFT"}' --keyring-backend test --label 'Test simple NFT' --no-admin --from dev01 -y
    cmd="starsd tx wasm instantiate {0} '".format(cw721_id)+cw721_init+"' --keyring-backend test --label 'Test simple NFT' --no-admin --output json -y --from dev01 2> /dev/null | jq '.txhash' | sed 's/\"//g;' | tr '\n' ' ' | tr -d ' '"
    cw721_instance01 = plan.exec(
        description="Instance cw721 NFT test",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    # sleep 5 seconds and check the tx, code_id should be 1
    # jq -r '.events | .[] | select(.type == "instantiate") | .attributes | .[] | select(.key == "_contract_address") | .value'
    filter = "jq -r '.events | .[] | select(.type == " + '\"instantiate\"' + ") | .attributes | .[] | select(.key == "+ '\"_contract_address\"' + ") | .value' | sed 's/\"//g;' | tr '\n' ' ' | tr -d ' '"
    cmd="sleep 10 && starsd q tx "+ "{0}".format(cw721_instance01) + " --output json | " + filter
    cw721_addr = plan.exec(
        description="txhash - get contract addr",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    contracts.update({"cw721_base": { "code_id": cw721_id, "addr": cw721_addr}})
    
    return { 
        "validator_addr" : validator_addr, 
        "dev_addr" : dev_addr, 
        "cw721_addr": cw721_addr,
        "contracts": contracts,
    }

def deploy_contracts(plan, contract_name, service_name):

    # deploy hyperlane smart contracts
    cmd="starsd tx wasm store {0}.wasm --keyring-backend test --gas-prices 0.025ustars --gas auto --gas-adjustment 1.7 --output json -y --from dev01 2> /dev/null | jq '.txhash' | sed 's/\"//g;' | tr '\n' ' ' | tr -d ' '".format(contract_name)
    txhash = plan.exec(
        description="Deploying smart contract [{0}]".format(contract_name),
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    filter = "jq -r '.events | .[] | select(.type == " + '\"store_code\"' + ") | .attributes | .[] | select(.key == "+ '\"code_id\"' + ") | .value' | sed 's/\"//g;' | tr '\n' ' ' | tr -d ' '"
    cmd="sleep 15 && starsd q tx "+ "{0}".format(txhash) + " --output json | " + filter
    contract_code_id = plan.exec(
        description="txhash - get contract addr",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    return contract_code_id