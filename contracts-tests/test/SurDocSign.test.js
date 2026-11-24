// SurDocSign: document timestamp, signatures (any number of signers per document) and multi-party envelopes with the three Foundation roles.
// IdentityRegistry and FoundationDAO are mocks at their fixed genesis addresses (only the getters SurDocSign reads).
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, setCodeOf, increaseTime, now, DAY } = require("./helpers");

const ZERO = ethers.ZeroAddress;
const ZH = ethers.ZeroHash;
const H1 = ethers.sha256(ethers.toUtf8Bytes("document one"));
const H2 = ethers.sha256(ethers.toUtf8Bytes("document two"));
const META = ethers.id("meta: title");
const N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141n;
const gasLog = {};

const T_SIGN = {
  DocumentSignature: [
    { name: "docHash", type: "bytes32" }, { name: "alg", type: "uint8" }, { name: "metaHash", type: "bytes32" },
    { name: "envelopeId", type: "bytes32" }, { name: "role", type: "uint8" }, { name: "deadline", type: "uint64" },
  ],
};
const T_CREATE = {
  EnvelopeCreate: [
    { name: "docHash", type: "bytes32" }, { name: "alg", type: "uint8" }, { name: "metaHash", type: "bytes32" },
    { name: "signersHash", type: "bytes32" }, { name: "foundationCountersign", type: "bool" }, { name: "minLevel", type: "uint8" },
    { name: "deadline", type: "uint64" }, { name: "salt", type: "bytes32" }, { name: "sigDeadline", type: "uint64" },
  ],
};
const T_CANCEL = { EnvelopeCancel: [{ name: "envelopeId", type: "bytes32" }, { name: "sigDeadline", type: "uint64" }] };

// abi.encodePacked(address[]) pads every element to 32 bytes
const signersHash = (list) => ethers.keccak256(ethers.concat(list.map((a) => ethers.zeroPadValue(a, 32))));
const asc = (list) => [...list].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));

async function fixture() {
  const S = await ethers.getSigners();
  const identity = await setCodeOf("MockSignIdentity", ADDR.IDENTITY_REGISTRY);
  const roles = await setCodeOf("MockFoundationRoles", ADDR.FOUNDATION_DAO);
  // S[10] ceo, S[11] chair, S[12] treasurer
  await roles.set(S[10].address, S[11].address, S[12].address);
  const c = await (await ethers.getContractFactory("SurDocSign")).deploy();
  const net = await ethers.provider.getNetwork();
  const domain = { name: "SurDocSign", version: "1", chainId: net.chainId, verifyingContract: await c.getAddress() };
  const t = await now();
  return { S, c, identity, roles, domain, t };
}

const sp = (docHash, o = {}) => ({ docHash, alg: 0, metaHash: META, envelopeId: ZH, role: 0, ...o });
const ep = (docHash, signers, t, o = {}) => ({
  docHash, alg: 0, metaHash: META, signers: asc(signers), foundationCountersign: false, minLevel: 0, deadline: t + 7 * DAY, salt: ethers.id("s" + Math.random()), ...o,
});

async function signSig(domain, signer, p, sigDeadline) {
  return signer.signTypedData(domain, T_SIGN, { ...p, deadline: sigDeadline });
}
async function createSig(domain, signer, p, sigDeadline) {
  return signer.signTypedData(domain, T_CREATE, {
    docHash: p.docHash, alg: p.alg, metaHash: p.metaHash, signersHash: signersHash(p.signers),
    foundationCountersign: p.foundationCountersign, minLevel: p.minLevel, deadline: p.deadline, salt: p.salt, sigDeadline,
  });
}
async function mkEnvelope(c, creator, p) {
  const id = await c.previewEnvelopeId(creator.address, p);
  await c.connect(creator).createEnvelope(p);
  return id;
}
async function record(label, txPromise) {
  const r = await (await txPromise).wait();
  gasLog[label] = Number(r.gasUsed);
  return r;
}

describe("SurDocSign", function () {
  after(() => console.log("\n      gas (Hardhat EVM):\n" + Object.entries(gasLog).map(([k, v]) => `        ${k}: ${v}`).join("\n")));

  describe("timestamp", () => {
    it("the first registration stores firstSeen and firstRegistrant; later ones only emit", async () => {
      const { S, c } = await loadFixture(fixture);
      await expect(record("register (first)", c.connect(S[1]).register(H1, 0, META))).to.emit(c, "DocumentRegistered").withArgs(H1, S[1].address, 0, META, true);
      const [seen, who, n] = await c.docInfo(H1);
      expect(seen).to.equal(await now());
      expect(who).to.equal(S[1].address);
      expect(n).to.equal(0);
      await increaseTime(100);
      await expect(record("register (repeat)", c.connect(S[2]).register(H1, 0, META))).to.emit(c, "DocumentRegistered").withArgs(H1, S[2].address, 0, META, false);
      const [seen2, who2] = await c.docInfo(H1);
      expect(seen2).to.equal(seen);
      expect(who2).to.equal(S[1].address);
    });
    it("rejects an empty hash and an unknown algorithm", async () => {
      const { S, c } = await loadFixture(fixture);
      await expect(c.connect(S[1]).register(ZH, 0, META)).to.be.revertedWith("SurDocSign: empty hash");
      await expect(c.connect(S[1]).register(H1, 2, META)).to.be.revertedWith("SurDocSign: unknown algorithm");
    });
  });

  describe("signatures outside an envelope: any number per document", () => {
    it("many different signers on one hash: each adds a signature, signerCount counts distinct signers", async () => {
      const { S, c } = await loadFixture(fixture);
      for (let i = 1; i <= 5; i++) {
        await expect(c.connect(S[i]).sign(sp(H1))).to.emit(c, "DocumentSigned");
        expect(await c.hasSigned(H1, S[i].address)).to.equal(true);
        expect(await c.signerCount(H1)).to.equal(i);
      }
      const [, , n] = await c.docInfo(H1);
      expect(n).to.equal(5);
      expect(await c.hasSigned(H1, S[6].address)).to.equal(false);
      expect(await c.hasSigned(H2, S[1].address)).to.equal(false);
      const [at] = await c.signatureOf(H1, ZH, S[3].address);
      expect(at).to.equal(await c.firstSignedAt(H1, S[3].address));
      expect(at).to.be.gt(0);
    });
    it("the same signer cannot sign the same hash twice outside an envelope", async () => {
      const { S, c } = await loadFixture(fixture);
      await record("sign (direct, standalone)", c.connect(S[1]).sign(sp(H1)));
      await expect(c.connect(S[1]).sign(sp(H1))).to.be.revertedWith("SurDocSign: already signed");
    });
    it("a signature on a new hash also registers it", async () => {
      const { S, c } = await loadFixture(fixture);
      await c.connect(S[1]).sign(sp(H1));
      const [seen, who] = await c.docInfo(H1);
      expect(seen).to.be.gt(0);
      expect(who).to.equal(S[1].address);
    });
    it("records the identity level at signing time: 0, 1, 2", async () => {
      const { S, c, identity } = await loadFixture(fixture);
      await identity.set(S[2].address, true, false);
      await identity.set(S[3].address, true, true);
      await c.connect(S[1]).sign(sp(H1));
      await c.connect(S[2]).sign(sp(H1));
      await c.connect(S[3]).sign(sp(H1));
      expect((await c.signatureOf(H1, ZH, S[1].address))[1]).to.equal(0);
      expect((await c.signatureOf(H1, ZH, S[2].address))[1]).to.equal(1);
      expect((await c.signatureOf(H1, ZH, S[3].address))[1]).to.equal(2);
      // a later change does not touch the record
      await identity.set(S[3].address, false, false);
      expect((await c.signatureOf(H1, ZH, S[3].address))[1]).to.equal(2);
    });
    it("an unreachable IdentityRegistry reads as level 0 and does not block signing", async () => {
      const { S, c } = await loadFixture(fixture);
      await hre.network.provider.send("hardhat_setCode", [ADDR.IDENTITY_REGISTRY, "0x"]);
      await c.connect(S[1]).sign(sp(H1));
      expect((await c.signatureOf(H1, ZH, S[1].address))[1]).to.equal(0);
    });
    it("rejects an empty hash, an unknown algorithm, a Foundation role and an unknown role outside an envelope", async () => {
      const { S, c } = await loadFixture(fixture);
      await expect(c.connect(S[1]).sign(sp(ZH))).to.be.revertedWith("SurDocSign: empty hash");
      await expect(c.connect(S[1]).sign(sp(H1, { alg: 2 }))).to.be.revertedWith("SurDocSign: unknown algorithm");
      await expect(c.connect(S[10]).sign(sp(H1, { role: 1 }))).to.be.revertedWith("SurDocSign: role needs an envelope");
      await expect(c.connect(S[1]).sign(sp(H1, { role: 4 }))).to.be.revertedWith("SurDocSign: unknown role");
    });
  });

  describe("signatures with an EIP-712 signature (relayed)", () => {
    it("anyone can submit; the signer is the one who signed", async () => {
      const { S, c, domain, t } = await loadFixture(fixture);
      const p = sp(H1);
      const dl = t + DAY;
      const sig = await signSig(domain, S[1], p, dl);
      await expect(record("signWithSig (relayed, standalone)", c.connect(S[0]).signWithSig(p, S[1].address, dl, sig)))
        .to.emit(c, "DocumentSigned").withArgs(H1, ZH, S[1].address, 0, 0, (await now()) + 1, S[0].address);
      expect(await c.hasSigned(H1, S[1].address)).to.equal(true);
    });
    it("rejects a signature by someone else, a changed field, an expired one, and a replay", async () => {
      const { S, c, domain, t } = await loadFixture(fixture);
      const p = sp(H1);
      const dl = t + DAY;
      const sig = await signSig(domain, S[1], p, dl);
      await expect(c.connect(S[0]).signWithSig(p, S[2].address, dl, sig)).to.be.revertedWith("SurDocSign: bad signature");
      await expect(c.connect(S[0]).signWithSig(sp(H2), S[1].address, dl, sig)).to.be.revertedWith("SurDocSign: bad signature");
      await expect(c.connect(S[0]).signWithSig(sp(H1, { metaHash: ZH }), S[1].address, dl, sig)).to.be.revertedWith("SurDocSign: bad signature");
      await expect(c.connect(S[0]).signWithSig(p, S[1].address, dl + 1, sig)).to.be.revertedWith("SurDocSign: bad signature");
      await c.connect(S[0]).signWithSig(p, S[1].address, dl, sig);
      await expect(c.connect(S[0]).signWithSig(p, S[1].address, dl, sig)).to.be.revertedWith("SurDocSign: already signed");
      const old = await signSig(domain, S[2], p, t + 10);
      await increaseTime(100);
      await expect(c.connect(S[0]).signWithSig(p, S[2].address, t + 10, old)).to.be.revertedWith("SurDocSign: signature expired");
    });
    it("a signature made for another contract or chain does not verify", async () => {
      const { S, c, domain, t } = await loadFixture(fixture);
      const p = sp(H1);
      const dl = t + DAY;
      const other = await signSig({ ...domain, verifyingContract: S[5].address }, S[1], p, dl);
      await expect(c.connect(S[0]).signWithSig(p, S[1].address, dl, other)).to.be.revertedWith("SurDocSign: bad signature");
      const otherChain = await signSig({ ...domain, chainId: 999n }, S[1], p, dl);
      await expect(c.connect(S[0]).signWithSig(p, S[1].address, dl, otherChain)).to.be.revertedWith("SurDocSign: bad signature");
    });
    it("accepts v as 0/1 and rejects a high-s (malleated) signature and a bad length", async () => {
      const { S, c, domain, t } = await loadFixture(fixture);
      const p = sp(H1);
      const dl = t + DAY;
      const sig = await signSig(domain, S[1], p, dl);
      const parsed = ethers.Signature.from(sig);
      const flipped = ethers.concat([parsed.r, ethers.toBeHex(N - BigInt(parsed.s), 32), ethers.toBeHex(parsed.v === 27 ? 28 : 27, 1)]);
      await expect(c.connect(S[0]).signWithSig(p, S[1].address, dl, flipped)).to.be.revertedWith("SurDocSign: high-s signature");
      await expect(c.connect(S[0]).signWithSig(p, S[1].address, dl, sig.slice(0, 130))).to.be.revertedWith("SurDocSign: bad signature length");
      const v01 = ethers.concat([parsed.r, parsed.s, ethers.toBeHex(parsed.v - 27, 1)]);
      await c.connect(S[0]).signWithSig(p, S[1].address, dl, v01);
      expect(await c.hasSigned(H1, S[1].address)).to.equal(true);
    });
  });

  describe("envelopes: creation", () => {
    it("creates an envelope; the id matches the preview; the event carries the list", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const p = ep(H1, [S[1].address, S[2].address, S[3].address], t);
      const id = await c.previewEnvelopeId(S[0].address, p);
      await expect(record("createEnvelope (3 named signers)", c.connect(S[0]).createEnvelope(p)))
        .to.emit(c, "EnvelopeCreated").withArgs(id, S[0].address, H1, 0, META, p.signers, false, 0, p.deadline);
      const info = await c.envelopeInfo(id);
      expect(info.creator).to.equal(S[0].address);
      expect(info.required).to.equal(3);
      expect(info.filled).to.equal(0);
      expect(await c.envelopeState(id)).to.equal(1);
      expect(await c.isNamedSigner(id, S[2].address)).to.equal(true);
      expect(await c.isNamedSigner(id, S[4].address)).to.equal(false);
      // creating it also registers the hash
      expect((await c.docInfo(H1))[0]).to.be.gt(0);
    });
    it("the same parameters from the same creator cannot be created twice; another salt or creator gives another id", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const p = ep(H1, [S[1].address], t);
      await c.connect(S[0]).createEnvelope(p);
      await expect(c.connect(S[0]).createEnvelope(p)).to.be.revertedWith("SurDocSign: envelope exists");
      const a = await c.previewEnvelopeId(S[0].address, p);
      expect(await c.previewEnvelopeId(S[5].address, p)).to.not.equal(a);
      expect(await c.previewEnvelopeId(S[0].address, { ...p, salt: ethers.id("other") })).to.not.equal(a);
      await c.connect(S[5]).createEnvelope(p);
    });
    it("rejects unsorted, duplicate and zero signers, no signers, and too many slots", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const [a, b] = asc([S[1].address, S[2].address]);
      await expect(c.connect(S[0]).createEnvelope({ ...ep(H1, [a], t), signers: [b, a] })).to.be.revertedWith("SurDocSign: signers must be ascending and non-zero");
      await expect(c.connect(S[0]).createEnvelope({ ...ep(H1, [a], t), signers: [a, a] })).to.be.revertedWith("SurDocSign: signers must be ascending and non-zero");
      await expect(c.connect(S[0]).createEnvelope({ ...ep(H1, [a], t), signers: [ZERO, a] })).to.be.revertedWith("SurDocSign: signers must be ascending and non-zero");
      await expect(c.connect(S[0]).createEnvelope(ep(H1, [], t))).to.be.revertedWith("SurDocSign: no signers");
      const many = (n) => Array.from({ length: n }, () => ethers.Wallet.createRandom().address);
      await c.connect(S[0]).createEnvelope(ep(H1, many(20), t));
      await expect(c.connect(S[0]).createEnvelope(ep(H1, many(21), t))).to.be.revertedWith("SurDocSign: too many signers");
      // roles count as slots: 18 named + 3 roles = 21
      await expect(c.connect(S[0]).createEnvelope(ep(H1, many(18), t, { foundationCountersign: true }))).to.be.revertedWith("SurDocSign: too many signers");
      await c.connect(S[0]).createEnvelope(ep(H1, many(17), t, { foundationCountersign: true }));
    });
    it("rejects an empty hash, an unknown algorithm, a bad level and a deadline out of range", async () => {
      const { S, c, t } = await loadFixture(fixture);
      await expect(c.connect(S[0]).createEnvelope(ep(ZH, [S[1].address], t))).to.be.revertedWith("SurDocSign: empty hash");
      await expect(c.connect(S[0]).createEnvelope(ep(H1, [S[1].address], t, { alg: 2 }))).to.be.revertedWith("SurDocSign: unknown algorithm");
      await expect(c.connect(S[0]).createEnvelope(ep(H1, [S[1].address], t, { minLevel: 3 }))).to.be.revertedWith("SurDocSign: bad level");
      await expect(c.connect(S[0]).createEnvelope(ep(H1, [S[1].address], t, { deadline: t + 60 }))).to.be.revertedWith("SurDocSign: deadline out of range");
      await expect(c.connect(S[0]).createEnvelope(ep(H1, [S[1].address], t, { deadline: t + 366 * DAY }))).to.be.revertedWith("SurDocSign: deadline out of range");
    });
    it("createEnvelopeWithSig: the creator is the signer, not the submitter", async () => {
      const { S, c, domain, t } = await loadFixture(fixture);
      const p = ep(H1, [S[1].address, S[2].address], t);
      const dl = t + DAY;
      const sig = await createSig(domain, S[3], p, dl);
      const id = await c.previewEnvelopeId(S[3].address, p);
      await record("createEnvelopeWithSig (relayed, 2 signers)", c.connect(S[0]).createEnvelopeWithSig(p, S[3].address, dl, sig));
      expect((await c.envelopeInfo(id)).creator).to.equal(S[3].address);
      await expect(c.connect(S[0]).createEnvelopeWithSig({ ...p, salt: ethers.id("x") }, S[3].address, dl, sig)).to.be.revertedWith("SurDocSign: bad signature");
      await expect(c.connect(S[0]).createEnvelopeWithSig(p, S[4].address, dl, sig)).to.be.revertedWith("SurDocSign: bad signature");
    });
  });

  describe("envelopes: signing and completion", () => {
    it("completes after every listed signer signed; the event and state follow", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [S[1].address, S[2].address, S[3].address], t));
      const e = (s) => sp(H1, { envelopeId: id });
      await record("sign (direct, in envelope)", c.connect(S[1]).sign(e()));
      await c.connect(S[2]).sign(e());
      expect(await c.isComplete(id)).to.equal(false);
      expect((await c.envelopeInfo(id)).filled).to.equal(2);
      await expect(c.connect(S[3]).sign(e())).to.emit(c, "EnvelopeCompleted").withArgs(id, H1, await now() + 1);
      expect(await c.isComplete(id)).to.equal(true);
      expect(await c.envelopeState(id)).to.equal(2);
      expect((await c.envelopeInfo(id)).completedAt).to.be.gt(0);
      // complete: nobody signs it again, not even a listed signer
      await expect(c.connect(S[1]).sign(e())).to.be.revertedWith("SurDocSign: already signed");
    });
    it("a signer who is not listed, a wrong document or wrong metadata cannot sign the envelope", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [S[1].address], t));
      await expect(c.connect(S[2]).sign(sp(H1, { envelopeId: id }))).to.be.revertedWith("SurDocSign: not a listed signer");
      await expect(c.connect(S[1]).sign(sp(H2, { envelopeId: id }))).to.be.revertedWith("SurDocSign: envelope mismatch");
      await expect(c.connect(S[1]).sign(sp(H1, { envelopeId: id, metaHash: ZH }))).to.be.revertedWith("SurDocSign: envelope mismatch");
      await expect(c.connect(S[1]).sign(sp(H1, { envelopeId: id, alg: 1 }))).to.be.revertedWith("SurDocSign: envelope mismatch");
      await expect(c.connect(S[1]).sign(sp(H1, { envelopeId: ethers.id("nope") }))).to.be.revertedWith("SurDocSign: unknown envelope");
    });
    it("a listed signer can also sign the same document outside the envelope, and in a second envelope; signerCount counts them once", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const id1 = await mkEnvelope(c, S[0], ep(H1, [S[1].address, S[2].address], t));
      const id2 = await mkEnvelope(c, S[0], ep(H1, [S[1].address], t));
      await c.connect(S[1]).sign(sp(H1));                       // outside
      await c.connect(S[1]).sign(sp(H1, { envelopeId: id1 }));  // envelope 1
      await c.connect(S[1]).sign(sp(H1, { envelopeId: id2 }));  // envelope 2
      await c.connect(S[2]).sign(sp(H1, { envelopeId: id1 }));
      expect(await c.signerCount(H1)).to.equal(2);
      expect(await c.isComplete(id1)).to.equal(true);
      expect(await c.isComplete(id2)).to.equal(true);
      expect((await c.signatureOf(H1, id1, S[1].address))[0]).to.be.gt(0);
      expect((await c.signatureOf(H1, id2, S[1].address))[0]).to.be.gt(0);
      expect((await c.signatureOf(H1, ZH, S[1].address))[0]).to.be.gt(0);
      expect((await c.signatureOf(H1, ZH, S[2].address))[0]).to.equal(0);
    });
    it("a signature with an EIP-712 signature fills an envelope slot", async () => {
      const { S, c, domain, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [S[1].address], t));
      const p = sp(H1, { envelopeId: id });
      const dl = t + DAY;
      await record("signWithSig (relayed, in envelope, completes)", c.connect(S[9]).signWithSig(p, S[1].address, dl, await signSig(domain, S[1], p, dl)));
      expect(await c.isComplete(id)).to.equal(true);
    });
    it("rejects signing after the deadline (state expired) and after cancellation", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [S[1].address, S[2].address], t, { deadline: t + 2 * DAY }));
      await c.connect(S[1]).sign(sp(H1, { envelopeId: id }));
      await increaseTime(3 * DAY);
      expect(await c.envelopeState(id)).to.equal(4);
      await expect(c.connect(S[2]).sign(sp(H1, { envelopeId: id }))).to.be.revertedWith("SurDocSign: envelope expired");
      const id2 = await mkEnvelope(c, S[0], ep(H2, [S[1].address], await now()));
      await c.connect(S[0]).cancelEnvelope(id2);
      await expect(c.connect(S[1]).sign(sp(H2, { envelopeId: id2 }))).to.be.revertedWith("SurDocSign: envelope cancelled");
    });
    it("minLevel: a signer below the level is refused, one at the level signs and the level is recorded", async () => {
      const { S, c, identity, t } = await loadFixture(fixture);
      await identity.set(S[2].address, true, false);
      await identity.set(S[3].address, true, true);
      const id1 = await mkEnvelope(c, S[0], ep(H1, [S[1].address, S[2].address], t, { minLevel: 1 }));
      await expect(c.connect(S[1]).sign(sp(H1, { envelopeId: id1 }))).to.be.revertedWith("SurDocSign: identity level too low");
      await c.connect(S[2]).sign(sp(H1, { envelopeId: id1 }));
      expect((await c.signatureOf(H1, id1, S[2].address))[1]).to.equal(1);
      const id2 = await mkEnvelope(c, S[0], ep(H2, [S[2].address, S[3].address], t, { minLevel: 2 }));
      await expect(c.connect(S[2]).sign(sp(H2, { envelopeId: id2 }))).to.be.revertedWith("SurDocSign: identity level too low");
      await c.connect(S[3]).sign(sp(H2, { envelopeId: id2 }));
      expect((await c.signatureOf(H2, id2, S[3].address))[1]).to.equal(2);
    });
  });

  describe("envelopes: Foundation roles", () => {
    it("a Foundation-only envelope (no named signers) completes after ceo, chair and treasurer signed, in any order", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [], t, { foundationCountersign: true }));
      expect((await c.envelopeInfo(id)).required).to.equal(3);
      await record("sign (Foundation role, in envelope)", c.connect(S[12]).sign(sp(H1, { envelopeId: id, role: 3 })));
      await c.connect(S[10]).sign(sp(H1, { envelopeId: id, role: 1 }));
      expect(await c.roleFilled(id, 1)).to.equal(true);
      expect(await c.roleFilled(id, 2)).to.equal(false);
      expect(await c.roleFilled(id, 3)).to.equal(true);
      expect(await c.isComplete(id)).to.equal(false);
      await expect(c.connect(S[11]).sign(sp(H1, { envelopeId: id, role: 2 }))).to.emit(c, "EnvelopeCompleted");
      expect((await c.signatureOf(H1, id, S[10].address))[2]).to.equal(1);
      expect((await c.signatureOf(H1, id, S[12].address))[2]).to.equal(3);
    });
    it("named signers and the three roles together", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [S[1].address], t, { foundationCountersign: true }));
      expect((await c.envelopeInfo(id)).required).to.equal(4);
      await c.connect(S[1]).sign(sp(H1, { envelopeId: id }));
      await c.connect(S[10]).sign(sp(H1, { envelopeId: id, role: 1 }));
      await c.connect(S[11]).sign(sp(H1, { envelopeId: id, role: 2 }));
      expect(await c.isComplete(id)).to.equal(false);
      await c.connect(S[12]).sign(sp(H1, { envelopeId: id, role: 3 }));
      expect(await c.isComplete(id)).to.equal(true);
    });
    it("a non-holder cannot take a role slot; a role needs a Foundation envelope; a role slot cannot be filled twice", async () => {
      const { S, c, roles, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [], t, { foundationCountersign: true }));
      await expect(c.connect(S[1]).sign(sp(H1, { envelopeId: id, role: 1 }))).to.be.revertedWith("SurDocSign: not the role holder");
      await expect(c.connect(S[10]).sign(sp(H1, { envelopeId: id, role: 2 }))).to.be.revertedWith("SurDocSign: not the role holder");
      await expect(c.connect(S[1]).sign(sp(H1, { envelopeId: id }))).to.be.revertedWith("SurDocSign: not a listed signer");
      const plain = await mkEnvelope(c, S[0], ep(H1, [S[1].address], t));
      await expect(c.connect(S[10]).sign(sp(H1, { envelopeId: plain, role: 1 }))).to.be.revertedWith("SurDocSign: envelope has no Foundation slots");
      // the ceo seat changes hands after the old ceo already signed: the slot is filled, the new ceo cannot fill it again
      await c.connect(S[10]).sign(sp(H1, { envelopeId: id, role: 1 }));
      await roles.set(S[13].address, S[11].address, S[12].address);
      await expect(c.connect(S[13]).sign(sp(H1, { envelopeId: id, role: 1 }))).to.be.revertedWith("SurDocSign: role already signed");
    });
    it("the role holder at signing time counts, not the one at creation", async () => {
      const { S, c, roles, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [], t, { foundationCountersign: true }));
      await roles.set(S[13].address, S[11].address, S[12].address);
      await expect(c.connect(S[10]).sign(sp(H1, { envelopeId: id, role: 1 }))).to.be.revertedWith("SurDocSign: not the role holder");
      await c.connect(S[13]).sign(sp(H1, { envelopeId: id, role: 1 }));
    });
    it("an address holding two roles fills only one slot, so that envelope cannot complete and its creator can cancel it", async () => {
      const { S, c, roles, t } = await loadFixture(fixture);
      await roles.set(S[10].address, S[10].address, S[12].address);
      const id = await mkEnvelope(c, S[0], ep(H1, [], t, { foundationCountersign: true }));
      await c.connect(S[10]).sign(sp(H1, { envelopeId: id, role: 1 }));
      await expect(c.connect(S[10]).sign(sp(H1, { envelopeId: id, role: 2 }))).to.be.revertedWith("SurDocSign: already signed");
      await c.connect(S[12]).sign(sp(H1, { envelopeId: id, role: 3 }));
      expect(await c.isComplete(id)).to.equal(false);
      await c.connect(S[0]).cancelEnvelope(id);
      expect(await c.envelopeState(id)).to.equal(3);
    });
    it("a named signer who currently holds a Foundation role is refused at creation (the envelope could never complete)", async () => {
      const { S, c, t } = await loadFixture(fixture);
      await expect(c.connect(S[0]).createEnvelope(ep(H1, [S[10].address], t, { foundationCountersign: true }))).to.be.revertedWith("SurDocSign: signer holds a Foundation role");
      // without Foundation slots the same address is an ordinary named signer
      await c.connect(S[0]).createEnvelope(ep(H1, [S[10].address], t));
    });
    it("an unreachable FoundationDAO means nobody can fill a role slot", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [], t, { foundationCountersign: true }));
      await hre.network.provider.send("hardhat_setCode", [ADDR.FOUNDATION_DAO, "0x"]);
      await expect(c.connect(S[10]).sign(sp(H1, { envelopeId: id, role: 1 }))).to.be.revertedWith("SurDocSign: not the role holder");
    });
  });

  describe("cancel", () => {
    it("only the creator, only before completion, only once; signatures already written stay", async () => {
      const { S, c, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [S[1].address, S[2].address], t));
      await c.connect(S[1]).sign(sp(H1, { envelopeId: id }));
      await expect(c.connect(S[1]).cancelEnvelope(id)).to.be.revertedWith("SurDocSign: not the creator");
      await expect(c.connect(S[0]).cancelEnvelope(ethers.id("nope"))).to.be.revertedWith("SurDocSign: unknown envelope");
      await expect(c.connect(S[0]).cancelEnvelope(id)).to.emit(c, "EnvelopeCancelled").withArgs(id, S[0].address);
      expect(await c.envelopeState(id)).to.equal(3);
      await expect(c.connect(S[0]).cancelEnvelope(id)).to.be.revertedWith("SurDocSign: already cancelled");
      expect((await c.signatureOf(H1, id, S[1].address))[0]).to.be.gt(0);
      const done = await mkEnvelope(c, S[0], ep(H2, [S[1].address], t));
      await c.connect(S[1]).sign(sp(H2, { envelopeId: done }));
      await expect(c.connect(S[0]).cancelEnvelope(done)).to.be.revertedWith("SurDocSign: envelope complete");
    });
    it("cancelEnvelopeWithSig: the creator signs, anyone submits", async () => {
      const { S, c, domain, t } = await loadFixture(fixture);
      const id = await mkEnvelope(c, S[0], ep(H1, [S[1].address], t));
      const dl = t + DAY;
      await expect(c.connect(S[9]).cancelEnvelopeWithSig(id, S[0].address, dl, await S[1].signTypedData(domain, T_CANCEL, { envelopeId: id, sigDeadline: dl }))).to.be.revertedWith("SurDocSign: bad signature");
      await c.connect(S[9]).cancelEnvelopeWithSig(id, S[0].address, dl, await S[0].signTypedData(domain, T_CANCEL, { envelopeId: id, sigDeadline: dl }));
      expect(await c.envelopeState(id)).to.equal(3);
    });
  });

  describe("state and views", () => {
    it("envelopeState: none, active, complete, cancelled, expired", async () => {
      const { S, c, t } = await loadFixture(fixture);
      expect(await c.envelopeState(ethers.id("none"))).to.equal(0);
      const a = await mkEnvelope(c, S[0], ep(H1, [S[1].address], t));
      expect(await c.envelopeState(a)).to.equal(1);
      await c.connect(S[1]).sign(sp(H1, { envelopeId: a }));
      expect(await c.envelopeState(a)).to.equal(2);
      const b = await mkEnvelope(c, S[0], ep(H2, [S[1].address], t, { deadline: t + 2 * DAY }));
      await increaseTime(3 * DAY);
      expect(await c.envelopeState(b)).to.equal(4);
      // completion beats expiry: a complete envelope stays complete after its deadline
      expect(await c.envelopeState(a)).to.equal(2);
    });
    it("roleFilled rejects an unknown role; the domain separator is for this contract and chain", async () => {
      const { c, domain } = await loadFixture(fixture);
      await expect(c.roleFilled(ZH, 0)).to.be.revertedWith("SurDocSign: unknown role");
      expect(await c.DOMAIN_SEPARATOR()).to.equal(ethers.TypedDataEncoder.hashDomain(domain));
    });
    it("holds no funds: plain transfers and ether with calls are refused", async () => {
      const { S, c } = await loadFixture(fixture);
      await expect(S[0].sendTransaction({ to: await c.getAddress(), value: 1n })).to.be.reverted;
      await expect(c.connect(S[0]).register(H1, 0, META, { value: 1n })).to.be.reverted;
    });
  });
});
