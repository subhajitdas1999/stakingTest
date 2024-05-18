async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const token = await ethers.deployContract("MyToken", [
    "Test Token",
    "TT",
    100,
  ]);
  const tokenAddress = await token.getAddress();
  console.log("token contract address:", tokenAddress);

  const Staking = await ethers.deployContract("Staking", [tokenAddress]);

  console.log("staking contract address:", await Staking.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
