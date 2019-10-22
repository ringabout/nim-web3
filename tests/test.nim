import ../web3
import chronos, nimcrypto, options, json, stint
import test_utils


#[ Contract NumberStorage
pragma solidity ^0.4.18;

contract NumberStorage {
   uint num;

   function setNumber(uint _num) public {
       num = _num;
   }

   function getNumber() public constant returns (uint) {
       return num;
   }
}
]#
contract(NumberStorage):
  proc setNumber(number: Uint256)
  proc getNumber(): Uint256 {.view.}

const NumberStorageCode = "6060604052341561000f57600080fd5b60bb8061001d6000396000f30060606040526004361060485763ffffffff7c01000000000000000000000000000000000000000000000000000000006000350416633fb5c1cb8114604d578063f2c9ecd8146062575b600080fd5b3415605757600080fd5b60606004356084565b005b3415606c57600080fd5b60726089565b60405190815260200160405180910390f35b600055565b600054905600a165627a7a7230582023e722f35009f12d5698a4ab22fb9d55a6c0f479fc43875c65be46fbdd8db4310029"

#[ Contract MetaCoin
pragma solidity >=0.4.25 <0.6.0;

contract MetaCoin {
    mapping (address => uint) balances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor() public {
        balances[tx.origin] = 10000;
    }

    function sendCoin(address receiver, uint amount) public returns(bool sufficient) {
        if (balances[msg.sender] < amount) return false;
        balances[msg.sender] -= amount;
        balances[receiver] += amount;
        emit Transfer(msg.sender, receiver, amount);
        return true;
    }

    function getBalance(address addr) public view returns(uint) {
        return balances[addr];
    }
}
]#
contract(MetaCoin):
  proc sendCoin(receiver: Address, amount: Uint256): Bool
  proc getBalance(address: Address): Uint256 {.view.}
  proc Transfer(fromAddr, toAddr: indexed[Address], value: Uint256) {.event.}
  proc BlaBla(fromAddr: indexed[Address]) {.event.}

const MetaCoinCode = "608060405234801561001057600080fd5b5032600090815260208190526040902061271090556101c2806100346000396000f30060806040526004361061004b5763ffffffff7c010000000000000000000000000000000000000000000000000000000060003504166390b98a118114610050578063f8b2cb4f14610095575b600080fd5b34801561005c57600080fd5b5061008173ffffffffffffffffffffffffffffffffffffffff600435166024356100d5565b604080519115158252519081900360200190f35b3480156100a157600080fd5b506100c373ffffffffffffffffffffffffffffffffffffffff6004351661016e565b60408051918252519081900360200190f35b336000908152602081905260408120548211156100f457506000610168565b336000818152602081815260408083208054879003905573ffffffffffffffffffffffffffffffffffffffff871680845292819020805487019055805186815290519293927fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef929181900390910190a35060015b92915050565b73ffffffffffffffffffffffffffffffffffffffff16600090815260208190526040902054905600a165627a7a72305820000313ec0ebbff4ffefbe79d615d0ab019d8566100c40eb95a4eee617a87d1090029"


proc test() {.async.} =
  let web3 = await newWeb3("ws://127.0.0.1:8545")
  let accounts = await web3.provider.eth_accounts()
  echo "accounts: ", accounts
  web3.defaultAccount = accounts[0]

  block: # NumberStorage
    let cc = await web3.deployContract(NumberStorageCode)
    echo "Deployed NumberStorage contract: ", cc

    let ns = web3.contractSender(NumberStorage, cc)

    echo "setnumber: ", await ns.setNumber(5.u256).send()

    let n = await ns.getNumber().call()
    assert(n == 5.u256)

  block: # MetaCoin
    let cc = await web3.deployContract(MetaCoinCode)
    echo "Deployed MetaCoin contract: ", cc

    let ns = web3.contractSender(MetaCoin, cc)

    let notifFut = newFuture[void]()
    var notificationsReceived = 0

    let s = await ns.subscribe(Transfer) do(fromAddr, toAddr: Address, value: Uint256):
      echo "onTransfer: ", fromAddr, " transferred ", value, " to ", toAddr
      inc notificationsReceived
      assert(fromAddr == web3.defaultAccount)
      assert((notificationsReceived == 1 and value == 50.u256) or
              (notificationsReceived == 2 and value == 100.u256))
      if notificationsReceived == 2:
        notifFut.complete()

    echo "getbalance: ", await ns.getBalance(web3.defaultAccount).call()

    echo "sendCoin: ", await ns.sendCoin(accounts[1], 50.u256).send()

    let newBalance1 = await ns.getBalance(web3.defaultAccount).call()
    assert(newBalance1 == 9950.u256)

    let newBalance2 = await ns.getBalance(accounts[1]).call()
    assert(newBalance2 == 50.u256)

    echo "sendCoin: ", await ns.sendCoin(accounts[1], 100.u256).send()

    await notifFut

    await s.unsubscribe()
  await web3.close()

waitFor test()
