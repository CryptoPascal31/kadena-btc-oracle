import shelve
import sys
import argparse
import aiohttp
import asyncio
from  more_itertools import chunked
from aiolimiter import AsyncLimiter

parser = argparse.ArgumentParser(description='Gen BTC Test vectors')

parser.add_argument('start', type=int)
parser.add_argument('stop', type=int)
parser.add_argument('--init-module', action="store_true")
parser.add_argument('--log', action="store_true")

args = parser.parse_args()

START = args.start
STOP = args.stop
INIT = args.init_module
LOG = args.log


limiter = AsyncLimiter(30,10.0)

async def _get_hash(session, height):
    async with limiter:
        async with session.get("https://mempool.space/api/block-height/{:d}".format(height)) as response:
            return await response.text()

async def _get_header(session, _hash):
    async with limiter:
        async with session.get("https://mempool.space/api/block/{:s}/header".format(_hash)) as response:
            return await response.text()

async def get_header(session, height):
    _hash = await _get_hash(session, height)
    if len(_hash)!=64:
        return None

    _header = await _get_header(session, _hash)
    if len(_header)!= 160:
        return None
    return _header

async def gen_file(start, stop, _init, _log):
    print("Writing test file {:d} => {:d}".format(start, stop))

    with open("vectors/blocks-{:d}-{:d}{:s}.repl".format(start, stop,"-init" if _init else ""), "w") as fd:
        async with aiohttp.ClientSession() as session:
            with shelve.open("blocks_cache.db") as db:
                fd.write("; Generated test scenario\n")

                async def __get(k):
                    _k = str(k)
                    if _k not in db:
                        header = await get_header(session, k)
                        if header:
                            db[_k] = bytes.fromhex(header)
                            print("Download {:d} => {:s}".format(k, header))
                        else:
                            print("{:d} => ERROR".format(k))
                    return db[_k].hex()

                if _init:
                    fd.write('(init-block "{:s}" {:d})\n'.format(await __get(start),start))
                    if _log:
                        fd.write('(print (format "INIT-BLOCK {{}}" [{:d}]))'.format(start))

                for c in chunked(range(start+1 if _init else start, stop+1),10):
                    for h in c:
                        fd.write('(report-block "{:s}")\n'.format(await __get(h)))
                    if _log:
                        fd.write('(print (format "REPORT-BLOCK {{}}" [{:d}]))\n'.format(h))

                fd.write("\n")

asyncio.run(gen_file(START, STOP, INIT, LOG))
