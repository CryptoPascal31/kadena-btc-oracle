import {} from 'dotenv/config'
import {Pact, createSignWithKeypair} from '@kadena/client'
import {local_pact, local_check, submit, status} from "./utils/pact.js";
import mempoolJS from "@mempool/mempool.js";
import {randomUUID} from 'node:crypto'

var lock = false;

const { bitcoin: { blocks } } = mempoolJS({hostname: 'mempool.space'});
const signer = createSignWithKeypair({ publicKey: process.env.SENDER_PUBKEY, secretKey: process.env.SENDER_PRIVKEY });

const make_nonce = () => "In_Brothers_We_Trust:"+randomUUID()

function kadena_tip()
{
  return local_pact(`(${process.env.ORACLE_MODULE}.get-tip)`, process.env.NETWORKID, process.env.CHAINID )
        .then(({height, "header-hash":hh, ...rest}) => ({height:parseInt(height.int), header_hash:BigInt(hh.int), ...rest}))
}

const single_transaction = header =>  Pact.builder.execution(`(${process.env.ORACLE_MODULE}.report-block (read-msg 'hdr))`)
                                                  .addData("hdr", header)
                                                  .setMeta({chainId:process.env.CHAINID, gasLimit:18000, gasPrice:1e-8, sender:process.env.SENDER})
                                                  .setNetworkId(process.env.NETWORKID)
                                                  .setNonce(make_nonce)
                                                  .addSigner(process.env.SENDER_PUBKEY, (signFor) => [signFor("coin.GAS")])
                                                  .createTransaction();

const bulk_transaction = header =>  Pact.builder.execution(`(map (${process.env.ORACLE_MODULE}.report-block) (read-msg 'hdr))`)
                                                .addData("hdr", header)
                                                .setMeta({chainId:process.env.CHAINID, gasLimit:17000*header.length, gasPrice:1e-8, sender:process.env.SENDER})
                                                .setNetworkId(process.env.NETWORKID)
                                                .setNonce(make_nonce)
                                                .addSigner(process.env.SENDER_PUBKEY, (signFor) => [signFor("coin.GAS")])
                                                .createTransaction();

async function do_report(header)
{
    lock = true;
    const cmd = header.length==1?single_transaction(header[0]):bulk_transaction(header);
    const signed_cmd = await signer(cmd)
    await local_check(signed_cmd)
          .then(()=> console.log("Local OK"))
          .then(() => submit(signed_cmd))
          .then(()=> console.log("Submitted"))
          .then(() => status(signed_cmd, process.env.NETWORKID, process.env.CHAINID))
          .then(x => console.log(x?.result?.status == "success"?"Report OK":"Report Error"))
          .finally(() => {console.log("-----------------------------------------");lock=false})
          .then(() => do_process())

}

const rev_endianess = v=> Array.from({length:32}, (_,i)=>v.slice(i*2,i*2+2)).reverse().join("")
const hash_to_bi = x => BigInt("0x"+rev_endianess(x))


async function do_process(verbose)
{
  if(lock)
    return;
  const btc_height = await blocks.getBlocksTipHeight();
  var {height:kadena_height, header_hash:kadena_tip_hash} = await kadena_tip();

  if(verbose)
    console.log(`Kadena Oracle Check ${btc_height} --> ${kadena_height}`)

  /* We check the Hash of the current Kadena Height on BTC to be sure we didn't record an orphan block */
  const tip_hash = await blocks.getBlockHeight({ height: kadena_height }).then(hash_to_bi);
  if(tip_hash != kadena_tip_hash)
  {
    console.log("Tip hashes don't match => Probably an Orphan block");
    console.log("Mempool hash:"+tip_hash);
    console.log("Kadena hash:"+kadena_tip_hash);
    kadena_height--;
  }

  if(kadena_height < btc_height)
  {
    const new_headers = []
    console.log(`Kadena Oracle needs update ${kadena_height} < ${btc_height}`)
    const target_height = Math.min(kadena_height+8, btc_height)

    for(let h=kadena_height+1; h<=target_height; h++)
    {
      const new_hash = await blocks.getBlockHeight({ height: h });
      const new_header = await blocks.getBlockHeader({ hash: new_hash });
      console.log(`Hash: ${new_hash}`)
      console.log(`Header: ${new_header}`)
      new_headers.push(new_header);
    }
    do_report(new_headers)
  }
}

async function run()
{
  console.log("Starting reporter")
  do_process(true)
  setInterval(do_process, 31_000);
  setInterval(()=>do_process(true), 2600_000);
}

run()
