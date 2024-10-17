def run(
    plan,
    dummy_mnemonic="", # this must be provided
    public_rpc_port=26657,
    public_p2p_port=26656,
    public_rest_port=1317,
    public_proxy_port=26658,
    public_grpc_port=9090,
    public_grpc_web_port=9091,
):

    #####
    # StarGaze
    #####

    plan.print("Stargaze service")

    service_name="stargaze-local"

    service_config=ServiceConfig(
        image="ghcr.io/lazychain/local-stargaze:v14.0.0-beta1",
        entrypoint = ["/data/entry-point.sh"],
        ports={ 
            "rpc": PortSpec(number=26657,transport_protocol="TCP",application_protocol="http"),
            "p2p": PortSpec(number=26656,transport_protocol="TCP",application_protocol="http"),
            "rest": PortSpec(number=1317,transport_protocol="TCP",application_protocol="http"),
             "grpc": PortSpec(number=9090,transport_protocol="TCP",application_protocol="http"),
            "grpc-web": PortSpec(number=9091,transport_protocol="TCP",application_protocol="http"),
        },
        public_ports={ 
            "rpc": PortSpec(number=public_rpc_port, transport_protocol="TCP",application_protocol="http"),
            "p2p": PortSpec(number=public_p2p_port,transport_protocol="TCP",application_protocol="http"),
            "rest": PortSpec(number=public_rest_port,transport_protocol="TCP",application_protocol="http"),
            "grpc": PortSpec(number=public_grpc_port,transport_protocol="TCP",application_protocol="http"),
            "grpc-web": PortSpec(number=public_grpc_web_port,transport_protocol="TCP",application_protocol="http"),
        },
    )

    stargaze = plan.add_service(name=service_name,config=service_config)

    # Create development account
    cmd = "echo \"{0}\" | starsd keys add dev01 --keyring-backend test --recover".format(dummy_mnemonic)
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
    cmd="starsd tx bank send {0} {1} 1000000000ustars --keyring-backend test --fees 75000ustars -y".format(validator_addr,dev_addr)
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

    cmd="starsd query bank balances {0}".format(dev_addr)
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

    cmd="curl -s -L -O https://github.com/public-awesome/cw-nfts/releases/download/v0.18.0/cw721_base.wasm"
    download_cw721 = plan.exec(
        description="Downloading cw721 base smart contract {0}".format(dev_addr),
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    # note: supress error output
    cmd="starsd tx wasm store cw721_base.wasm --keyring-backend test --gas-prices 0.025ustars --gas auto --gas-adjustment 1.7 --output json -y --from dev01 2> /dev/null | jq '.txhash' | sed 's/\"//g;' | tr '\n' ' ' | tr -d ' '"
    deploy_cw721 = plan.exec(
        description="Deploying cw721 base smart contract {0}".format(dev_addr),
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    plan.print(deploy_cw721)

    # sleep 5 seconds and check the tx, code_id should be 1
    # make this work:  && starsd q tx {0} | jq -r '.logs[0].events[-1].attributes[0].value' | sed 's/\"//g;' | tr '\n' ' ' | tr -d ' '".format(deploy_cw721)
    cmd="sleep 5"
    cw721_id = plan.exec(
        description="Txhash - get contract_id",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                cmd,
            ]
        ),
    )["output"]

    cw721_id = 1

    #https://github.com/public-awesome/cw-nfts/blob/a5abe476c1028b2563f995adab184b86e3fc03ff/packages/cw721/src/msg.rs#L126
    # be aware that format "strips" characters like \"
    cw721_init='{\"name\":\"TestNFT\",\"symbol\":\"LazyNFT\",\"minter\":\"' +"{0}".format(dev_addr)+'\"}'

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
    cmd="sleep 5 && starsd q tx "+ "{0}".format(cw721_instance01) + " --output json | " + filter
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

    return { "validator_addr" : validator_addr, "dev_addr" : dev_addr, "cw721_addr": cw721_addr }