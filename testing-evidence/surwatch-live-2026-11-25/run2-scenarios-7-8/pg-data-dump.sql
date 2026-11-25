--
-- PostgreSQL database dump
--

\restrict B4BiveSM9UxND6dFlVyPHhZkxU2zWvwj9qmvQdMfycOUzzleVtmWaVieJ7aPbAv

-- Dumped from database version 15.18 (Debian 15.18-1.pgdg13+1)
-- Dumped by pg_dump version 15.18 (Debian 15.18-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: agent_keys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.agent_keys (owner, operator, node_id, agent_address, registered_at, revoked_at, last_seq) FROM stdin;
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	0x45899aec1488da1831ea65a879f62e460631284d	422b169fb08dc88fd5206670de64207a33cbcdb3619486d3f9536c68f72a09945173fcfd107dd2966aeb5b9f6a8e2003b3e64e48bc857303db2f5c8f235266cf	0xfba1e9025455bbae83fab138af6b5d16287ee129	2026-11-25 15:29:36.562592+00	\N	43
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	0x558d023212b40072f18de63e27adace57541b746	afb47d76d2e2ec3226c49f27fb7dbe8390b6a7197cd31f059c8edce9b14af470a3d96a56a7ee3d943e40e517bf5d3ea4ffec90dbdc0a49cd61e5cfcfbd34b777	0x62242ea66c1c57d35ae09e588f0a564795015208	2026-11-25 15:29:46.91301+00	\N	43
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	0xf7ab920c3c19d225a9f6c2ee05599150f4d128f6	6a63fd39eae71f791ca03ddf0ff7c7f675177b28cc80f0fd0ba8ec30a122bfc070f161fb297305f4ae9685d47fec8133e49af6747866651a26d4977a6c8fd29d	0x7bbdb530c6d51c9891db1219f430c256f4e36104	2026-11-25 15:30:04.786584+00	\N	43
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	0x5bacebcfdad4d946b184276309a0b8b0a28ab608	2ee39b7b2596c0c76fb2ea87086e4c58a289cfd0289c916db47eaec04e1f4c8db14f441259e9be70e44b0ce2e24ba2f808884be2b0d700384f655b5460062614	0xa8ff9c78796e5aa423661b1a4df58b4b49fccc36	2026-11-25 15:30:11.410623+00	\N	43
0x6dd6c111587b2124bbd315e451216dab566c609e	0xa6b2f6d6c03a21f62b6ebf41ad4dd0b7464861bf	77fc693461750f739b225c9745e8741139ea836b7ae9d8d3938b90edbef9006ceb8665b5373815e794387b4767d68d03288d166ad1f1e9c040e673d732ce88eb	0xc41360617d3c789036dd32c04d5460753283e749	2026-11-25 15:30:17.477537+00	\N	43
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	0x2d481c5cb134f362c39ee2034e754a1b801b6658	16a9c965eb9358f58a5944dd5267cb822de2318b102d46985d0a14b950c4e38162586253bed0b273f66249d617c3c0304f60dc0957e4a1776c76cf7c77cd0d20	0x9a344390b99a2cd511f5c06a0fee82cd6d3f78fb	2026-11-25 15:29:54.230366+00	\N	27
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	0x379aa0d55f82c299be13f3daacdc6dbb080a3e6e	b4038b4e2170f07fc9f09e09239d6ff55104bb3aa6891182bb746a410543505f19729590925cae92221c58e576c0d2193376fa23b7d64d67614b5d8cd588d951	0xed12b46c98a13e880b86febb414a07a6af0b2aa7	2026-11-25 15:29:28.658727+00	\N	44
\.


--
-- Data for Name: alerts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.alerts (id, episode_id, type, owner, started_at, created_at, broad, rules_version) FROM stdin;
1	d0cb6552-1795620812	NODE_DOWN	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:33:32.192693+00	2026-11-25 15:44:32.192851+00	f	watch-rules-v1
2	cc7185d2-1795620932	AGENT_SILENT	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:32.192642+00	2026-11-25 15:46:32.192631+00	f	watch-rules-v1
3	cc7185d2-1795620932	RECOVERED	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:32.192642+00	2026-11-25 15:54:14.614169+00	f	watch-rules-v1
4	d0cb6552-1795620812	RECOVERED	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:33:32.192693+00	2026-11-25 15:54:14.614169+00	f	watch-rules-v1
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_log (id, at, actor, action, detail, prev_hash, hash) FROM stdin;
1	2026-11-25 15:29:28.658727+00	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	register_agent	agent 0xed12b46c98a13e880b86febb414a07a6af0b2aa7		2a2fc8682d990d2c1057f6d3bfe1ed7d8a426f957fa94a9ccb60f06e6526e581
2	2026-11-25 15:31:52.326485+00	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	set_manager	from 0x to 0xf8a1…3577	2a2fc8682d990d2c1057f6d3bfe1ed7d8a426f957fa94a9ccb60f06e6526e581	94443e8a92a66bcfaac191198d747345ebadf0e2fc5a0889c49003019b3abc94
3	2026-11-25 15:32:00.908282+00	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	set_manager	from 0xf8a1…3577 to 0xf8a1…3577	94443e8a92a66bcfaac191198d747345ebadf0e2fc5a0889c49003019b3abc94	094687cb6b3ae9e53192e880d3fd18b3881528b8edd011153eaf8a09909e0d4e
4	2026-11-25 16:01:42.246412+00	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	read_contacts	7 validators	094687cb6b3ae9e53192e880d3fd18b3881528b8edd011153eaf8a09909e0d4e	e13a5fad2c0b8ad9b0421c68594fc6306c2a524894a7bdb086a999a0b2070efd
5	2026-11-25 16:02:03.684629+00	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	read_contacts	7 validators	e13a5fad2c0b8ad9b0421c68594fc6306c2a524894a7bdb086a999a0b2070efd	6439c5dad253f4082ccbb8b98b92a74873229dfe468d8c2f19015e2974e75bf7
6	2026-11-25 16:12:06.560148+00	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	read_contacts	7 validators	6439c5dad253f4082ccbb8b98b92a74873229dfe468d8c2f19015e2974e75bf7	a4b08d37e6307c82309063ee8e3ed978e318fdcb19db750e92a01970f6816454
7	2026-11-25 16:12:27.591373+00	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	read_contacts	7 validators	a4b08d37e6307c82309063ee8e3ed978e318fdcb19db750e92a01970f6816454	8f6c533f2b93f1d743782ee48b6dbd7e4ce39b0885d28b525a75d82a96c3c306
\.


--
-- Data for Name: check_results; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.check_results (owner, at, state, code, signals, rules_version) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:23:32.192136+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:24:32.193159+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:25:32.192187+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:26:32.195987+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:27:32.192798+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:29:32.192387+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 30}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 22}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 25}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 22}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 25}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 25}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:32:32.19241+00	UNKNOWN	P2P_UNSEEN	{"s1": true, "s2": true, "s3": {"mon": false}, "lag": 17}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 20}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 27}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:33:32.192693+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 325}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 43}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:34:32.192691+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 341}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:32.192642+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:35:32.192642+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 359}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:36:32.192192+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:36:32.192192+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 375}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:37:32.192318+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:37:32.192318+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 390}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:38:32.192062+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:38:32.192062+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 407}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:39:32.192226+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:39:32.192226+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 425}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:40:32.19196+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:40:32.19196+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 440}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:42:32.192679+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:42:32.192679+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 473}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:41:32.192199+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:41:32.192199+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 455}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:43:32.192184+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:43:32.192184+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 490}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:44:32.192851+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:44:32.192851+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 505}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:45:32.191963+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:45:32.191963+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 521}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:46:32.192631+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:46:32.192631+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 539}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:48:14.61454+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:48:14.61454+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 566}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 9}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:49:14.61422+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:49:14.61422+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 581}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:50:14.613712+00	NODE_STUCK		{"s1": true, "s2": false, "s3": {"mon": true}, "lag": 601}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:02:14.614058+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:02:14.614058+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:02:14.614058+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:02:14.614058+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:02:14.614058+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:02:14.614058+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:02:14.614058+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:03:14.613612+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:03:14.613612+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:03:14.613612+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:03:14.613612+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:03:14.613612+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:03:14.613612+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:03:14.613612+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:04:14.614094+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:04:14.614094+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:04:14.614094+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:04:14.614094+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:04:14.614094+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:04:14.614094+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:04:14.614094+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:05:14.613731+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:05:14.613731+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:05:14.613731+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:05:14.613731+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:05:14.613731+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:05:14.613731+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:05:14.613731+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:06:44.379644+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:06:44.379644+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:06:44.379644+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:06:44.379644+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:06:44.379644+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:06:44.379644+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:06:44.379644+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:07:44.379893+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:07:44.379893+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:07:44.379893+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:07:44.379893+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:07:44.379893+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:07:44.379893+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:07:44.379893+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:08:44.37952+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:08:44.37952+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:08:44.37952+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:08:44.37952+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:08:44.37952+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:08:44.37952+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:08:44.37952+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:09:44.379704+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:09:44.379704+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:09:44.379704+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:09:44.379704+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:09:44.379704+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:09:44.379704+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:09:44.379704+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:10:44.379611+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:10:44.379611+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:10:44.379611+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:10:44.379611+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:10:44.379611+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:10:44.379611+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:10:44.379611+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:11:44.379677+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:11:44.379677+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:11:44.379677+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:11:44.379677+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:11:44.379677+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:11:44.379677+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:11:44.379677+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
\.


--
-- Data for Name: contacts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.contacts (owner, channel, value, state, verified_at, fail_count, updated_at) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	telegram	xOB22amqIVX8kbYHd8y1am53+RgajVgH43B3c16eP+8=	verified	2026-11-25 15:31:19.925885+00	0	2026-11-25 15:31:19.925885+00
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	telegram	NNcmBNt4Z/lkJq+2j/6AlIdcfp0l4IDf3RWyZTO+7/8=	verified	2026-11-25 15:31:38.383927+00	0	2026-11-25 15:54:29.56625+00
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	telegram	QVcclFjBofQ4hMnaAi85NNjJ0g3s5cge0m8iArmAiFE=	verified	2026-11-25 15:31:32.769841+00	0	2026-11-25 15:54:29.569991+00
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	telegram	XkcbLobjeLfz04+EqDLtws2JJaz2WInQ1H1oyiulbb8=	verified	2026-11-25 15:31:26.14891+00	0	2026-11-25 15:54:29.572532+00
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	email	fO/2AMdcQL2Gq/Jtmo/rCwtllX58pdOIUMpkY2JE/t5mwXirCB8JbSvoexM=	verified	2026-11-25 15:31:43.964189+00	0	2026-11-25 15:54:29.575655+00
\.


--
-- Data for Name: cursors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cursors (key, value) FROM stdin;
poll_offset_telegram	104
notifier_alert_id	4
registry_scan_block	1067
notifier_undeliverable_alert_id	4
\.


--
-- Data for Name: deliveries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.deliveries (id, alert_id, episode_id, kind, recipient, role, channel, state, attempts, next_at, last_error, body, created_at, sent_at) FROM stdin;
2	1	d0cb6552-1795620812	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	telegram	sent	1	2026-11-25 15:44:46.858146+00		🔴 نود ولیدیتور از ۱۱ دقیقه پیش در دسترس نیست\nولیدیتور: 0xd0cb…1dd2   وضعیت: NODE_DOWN\nآخرین ضربان: ۱۹:۱۳\nآپ‌تایم ۲۴ ساعت: ۱۴٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:44:46.858146+00	2026-11-25 15:44:46.863345+00
3	1	d0cb6552-1795620812	alert	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	manager	telegram	sent	1	2026-11-25 15:44:46.859335+00		🔴 نود ولیدیتور از ۱۱ دقیقه پیش در دسترس نیست\nولیدیتور: 0xd0cb…1dd2   وضعیت: NODE_DOWN\nآخرین ضربان: ۱۹:۱۳\nآپ‌تایم ۲۴ ساعت: ۱۴٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:44:46.859335+00	2026-11-25 15:44:46.872428+00
1	1	d0cb6552-1795620812	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	email	sent	1	2026-11-25 15:44:46.856467+00		🔴 نود ولیدیتور از ۱۱ دقیقه پیش در دسترس نیست\nولیدیتور: 0xd0cb…1dd2   وضعیت: NODE_DOWN\nآخرین ضربان: ۱۹:۱۳\nآپ‌تایم ۲۴ ساعت: ۱۴٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:44:46.856467+00	2026-11-25 15:44:46.878017+00
4	2	cc7185d2-1795620932	alert	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	owner	telegram	sent	1	2026-11-25 15:46:46.853791+00		🟡 ایجنت ولیدیتور ۱۱ دقیقه است ضربان نمی‌فرستد (نود در شبکه دیده می‌شود)\nولیدیتور: 0xcc71…28d0   وضعیت: AGENT_SILENT\nآخرین ضربان: ۱۹:۰۱   آخرین ارتفاع دیده‌شده: ۲۹۸\nآپ‌تایم ۲۴ ساعت: ۱۰۰٫۰٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:46:46.853791+00	2026-11-25 15:46:46.857637+00
5	3	cc7185d2-1795620932	alert	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	owner	telegram	sent	1	2026-11-25 15:54:29.561383+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۱۹ دقیقه)\nولیدیتور: 0xcc71…28d0   وضعیت: UP\nآخرین ضربان: ۱۹:۲۴   آخرین ارتفاع دیده‌شده: ۷۲۷\nآپ‌تایم ۲۴ ساعت: ۱۰۰٫۰٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:54:29.561383+00	2026-11-25 15:54:29.56625+00
7	4	d0cb6552-1795620812	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	telegram	sent	1	2026-11-25 15:54:29.563723+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۲۱ دقیقه)\nولیدیتور: 0xd0cb…1dd2   وضعیت: UP\nآخرین ضربان: ۱۹:۲۳   آخرین ارتفاع دیده‌شده: ۷۰۸\nآپ‌تایم ۲۴ ساعت: ۲۵٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:54:29.563723+00	2026-11-25 15:54:29.569991+00
8	4	d0cb6552-1795620812	alert	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	manager	telegram	sent	1	2026-11-25 15:54:29.564546+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۲۱ دقیقه)\nولیدیتور: 0xd0cb…1dd2   وضعیت: UP\nآخرین ضربان: ۱۹:۲۳   آخرین ارتفاع دیده‌شده: ۷۰۸\nآپ‌تایم ۲۴ ساعت: ۲۵٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:54:29.564546+00	2026-11-25 15:54:29.572532+00
6	4	d0cb6552-1795620812	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	email	sent	1	2026-11-25 15:54:29.563466+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۲۱ دقیقه)\nولیدیتور: 0xd0cb…1dd2   وضعیت: UP\nآخرین ضربان: ۱۹:۲۳   آخرین ارتفاع دیده‌شده: ۷۰۸\nآپ‌تایم ۲۴ ساعت: ۲۵٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:54:29.563466+00	2026-11-25 15:54:29.575655+00
\.


--
-- Data for Name: engine_state; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.engine_state (owner, payload) FROM stdin;
0x6dd6c111587b2124bbd315e451216dab566c609e	{"Code": "", "Sent": null, "Owner": "0x6dd6c111587b2124bbd315e451216dab566c609e", "Since": "2026-11-25T16:11:44.379677982Z", "State": "UP", "UpSince": "2026-11-25T16:11:44.379677982Z", "LastTick": "2026-11-25T16:11:44.379677982Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	{"Code": "", "Sent": null, "Owner": "0xb0b3fff6193b77c818f3b7733e1966d60cf8239e", "Since": "2026-11-25T16:11:44.379677982Z", "State": "UP", "UpSince": "2026-11-25T16:11:44.379677982Z", "LastTick": "2026-11-25T16:11:44.379677982Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	{"Code": "", "Sent": null, "Owner": "0xcc7185d2082e647e2d3643596d626ab2f8f028d0", "Since": "2026-11-25T16:11:44.379677982Z", "State": "UP", "UpSince": "2026-11-25T16:11:44.379677982Z", "LastTick": "2026-11-25T16:11:44.379677982Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	{"Code": "", "Sent": null, "Owner": "0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2", "Since": "2026-11-25T16:11:44.379677982Z", "State": "UP", "UpSince": "2026-11-25T16:11:44.379677982Z", "LastTick": "2026-11-25T16:11:44.379677982Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	{"Code": "", "Sent": null, "Owner": "0xf8a13c5a99e617cb22eb184d14266de4b82d3577", "Since": "2026-11-25T16:11:44.379677982Z", "State": "UP", "UpSince": "2026-11-25T16:11:44.379677982Z", "LastTick": "2026-11-25T16:11:44.379677982Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	{"Code": "", "Sent": null, "Owner": "0x10e3f7133f3fc58a30b17ae57846278dbab4044f", "Since": "2026-11-25T16:11:44.379677982Z", "State": "UP", "UpSince": "2026-11-25T16:11:44.379677982Z", "LastTick": "2026-11-25T16:11:44.379677982Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	{"Code": "", "Sent": null, "Owner": "0x3481a641697c8706d924ede2fa2ed7fd40b25e9c", "Since": "2026-11-25T16:11:44.379677982Z", "State": "UP", "UpSince": "2026-11-25T16:11:44.379677982Z", "LastTick": "2026-11-25T16:11:44.379677982Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
\.


--
-- Data for Name: heartbeats_latest; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.heartbeats_latest (owner, recv_at, head_changed_at, payload) FROM stdin;
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:11:49.163337+00	2026-11-25 16:11:49.163337+00	{"v": 1, "ts": 1795623109, "seq": 43, "owner": "0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2", "peers": 7, "nodeId": "afb47d76d2e2ec3226c49f27fb7dbe8390b6a7197cd31f059c8edce9b14af470a3d96a56a7ee3d943e40e517bf5d3ea4ffec90dbdc0a49cd61e5cfcfbd34b777", "rpc_ok": true, "rtt_ms": 3, "chainId": 262025, "cpu_pct": 30, "mem_pct": 42, "syncing": false, "operator": "0x558d023212b40072f18de63e27adace57541b746", "head_hash": "0xc4be0e6a0f51b9f293facbb326227eec25dc323d9945c934113b97e5f634c105", "load_x100": 528, "head_number": 1248, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 165}
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:12:13.788569+00	2026-11-25 16:12:13.788569+00	{"v": 1, "ts": 1795623133, "seq": 43, "owner": "0x10e3f7133f3fc58a30b17ae57846278dbab4044f", "peers": 7, "nodeId": "2ee39b7b2596c0c76fb2ea87086e4c58a289cfd0289c916db47eaec04e1f4c8db14f441259e9be70e44b0ce2e24ba2f808884be2b0d700384f655b5460062614", "rpc_ok": true, "rtt_ms": 4, "chainId": 262025, "cpu_pct": 35, "mem_pct": 42, "syncing": false, "operator": "0x5bacebcfdad4d946b184276309a0b8b0a28ab608", "head_hash": "0xe6a23b1e6b827c4e10deded27328e5e7794993a4fec8da2eddb96b051f92d48f", "load_x100": 862, "head_number": 1260, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 794}
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:12:27.120062+00	2026-11-25 16:12:27.120062+00	{"v": 1, "ts": 1795623147, "seq": 27, "owner": "0xcc7185d2082e647e2d3643596d626ab2f8f028d0", "peers": 7, "nodeId": "16a9c965eb9358f58a5944dd5267cb822de2318b102d46985d0a14b950c4e38162586253bed0b273f66249d617c3c0304f60dc0957e4a1776c76cf7c77cd0d20", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 33, "mem_pct": 42, "syncing": false, "operator": "0x2d481c5cb134f362c39ee2034e754a1b801b6658", "head_hash": "0x1d604e3308ed6e1477cee64959ec498f9cc7179d677fd3cfec8486dbaf7718cf", "load_x100": 981, "head_number": 1267, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 129}
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:12:20.018905+00	2026-11-25 16:12:20.018905+00	{"v": 1, "ts": 1795623139, "seq": 43, "owner": "0x6dd6c111587b2124bbd315e451216dab566c609e", "peers": 7, "nodeId": "77fc693461750f739b225c9745e8741139ea836b7ae9d8d3938b90edbef9006ceb8665b5373815e794387b4767d68d03288d166ad1f1e9c040e673d732ce88eb", "rpc_ok": true, "rtt_ms": 9, "chainId": 262025, "cpu_pct": 34, "mem_pct": 42, "syncing": false, "operator": "0xa6b2f6d6c03a21f62b6ebf41ad4dd0b7464861bf", "head_hash": "0x856f607112a572e11db08df1924b74923b6de3db51bee2ae7fdfe42ef279667e", "load_x100": 833, "head_number": 1263, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 6}
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:12:32.261245+00	2026-11-25 16:12:32.261245+00	{"v": 1, "ts": 1795623152, "seq": 44, "owner": "0xb0b3fff6193b77c818f3b7733e1966d60cf8239e", "peers": 7, "nodeId": "b4038b4e2170f07fc9f09e09239d6ff55104bb3aa6891182bb746a410543505f19729590925cae92221c58e576c0d2193376fa23b7d64d67614b5d8cd588d951", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 32, "mem_pct": 42, "syncing": false, "operator": "0x379aa0d55f82c299be13f3daacdc6dbb080a3e6e", "head_hash": "0xdb708a5cf7e6a685bb0c695624170101270cd6f2113ad3d2a49b737af11022e3", "load_x100": 1054, "head_number": 1270, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 255}
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:11:42.752723+00	2026-11-25 16:11:42.752723+00	{"v": 1, "ts": 1795623102, "seq": 43, "owner": "0xf8a13c5a99e617cb22eb184d14266de4b82d3577", "peers": 6, "nodeId": "422b169fb08dc88fd5206670de64207a33cbcdb3619486d3f9536c68f72a09945173fcfd107dd2966aeb5b9f6a8e2003b3e64e48bc857303db2f5c8f235266cf", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 28, "mem_pct": 41, "syncing": false, "operator": "0x45899aec1488da1831ea65a879f62e460631284d", "head_hash": "0x63fc437d16129836c021d198b1634e12d133060201edee6320e51f7ef0c484fc", "load_x100": 539, "head_number": 1245, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 623}
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:12:07.846845+00	2026-11-25 16:12:07.846845+00	{"v": 1, "ts": 1795623127, "seq": 43, "owner": "0x3481a641697c8706d924ede2fa2ed7fd40b25e9c", "peers": 7, "nodeId": "6a63fd39eae71f791ca03ddf0ff7c7f675177b28cc80f0fd0ba8ec30a122bfc070f161fb297305f4ae9685d47fec8133e49af6747866651a26d4977a6c8fd29d", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 34, "mem_pct": 42, "syncing": false, "operator": "0xf7ab920c3c19d225a9f6c2ee05599150f4d128f6", "head_hash": "0x54c66500f87de3ba85aa8c6a63d0015d5665c4be755cd02d72bc5964ea51369e", "load_x100": 833, "head_number": 1257, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 852}
\.


--
-- Data for Name: link_codes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.link_codes (code_hash, owner, channel, value, expires_at, used_at) FROM stdin;
907d32046f04b3e15d78abfd9daa4e2bf27c05ca28ab668f18ba851cf803c458	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	telegram		2026-11-25 15:41:19.74386+00	2026-11-25 15:31:19.92505+00
ae0cd990a85543f372c64d7ed5de5ff8b61085747d93071e5c7033e055301192	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	telegram		2026-11-25 15:41:26.076262+00	2026-11-25 15:31:26.1485+00
6ee462b34c9116234c15397a3420b00524d4d06c3547f07d8409bc2f1b1ef7ff	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	telegram		2026-11-25 15:41:32.579761+00	2026-11-25 15:31:32.768941+00
3e4e38e63b5e58784d9b3ed46bf8931833a6473d208cddb59d549bad2e07b3cd	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	telegram		2026-11-25 15:41:38.290272+00	2026-11-25 15:31:38.383579+00
b25c6dd318504bf8be159d5751a444da6dc86866829902c1b539f339ae4cc2f7	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	email	fO/2AMdcQL2Gq/Jtmo/rCwtllX58pdOIUMpkY2JE/t5mwXirCB8JbSvoexM=	2026-11-25 15:41:43.954523+00	2026-11-25 15:31:43.963865+00
\.


--
-- Data for Name: maintenance_windows; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.maintenance_windows (id, owner, start_at, end_at) FROM stdin;
\.


--
-- Data for Name: settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.settings (key, value) FROM stdin;
manager_address	0xf8a13c5a99e617cb22eb184d14266de4b82d3577
\.


--
-- Data for Name: state_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.state_log (id, owner, at, from_state, to_state, code, episode_id) FROM stdin;
1	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:23:32.192136+00		UNKNOWN	NOT_REGISTERED	
2	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
3	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
4	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
5	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
6	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
7	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
8	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:29:32.192387+00	UNKNOWN	AGENT_SILENT		
9	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
10	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
11	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
12	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:30:32.192101+00	AGENT_SILENT	UP		
13	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
14	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
15	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
16	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:32:32.19241+00	UP	UNKNOWN	P2P_UNSEEN	
17	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:33:32.192693+00	UNKNOWN	NODE_DOWN		
18	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:32.192642+00	UP	AGENT_SILENT		
19	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:50:14.613712+00	AGENT_SILENT	UP		cc7185d2-1795620932
20	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:50:14.613712+00	NODE_DOWN	NODE_STUCK		d0cb6552-1795620812
21	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:51:14.614081+00	NODE_STUCK	UP		d0cb6552-1795620812
22	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
23	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
24	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
25	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
26	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
27	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
28	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
29	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
30	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
31	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
32	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
33	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
34	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
35	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
36	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:06:44.379644+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
37	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:06:44.379644+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
38	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:06:44.379644+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
39	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:06:44.379644+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
40	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:06:44.379644+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
41	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:06:44.379644+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
42	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:06:44.379644+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
43	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:11:44.379677+00	UNKNOWN	UP		
44	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:11:44.379677+00	UNKNOWN	UP		
45	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:11:44.379677+00	UNKNOWN	UP		
46	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:11:44.379677+00	UNKNOWN	UP		
47	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:11:44.379677+00	UNKNOWN	UP		
48	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:11:44.379677+00	UNKNOWN	UP		
49	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:11:44.379677+00	UNKNOWN	UP		
\.


--
-- Data for Name: uptime_buckets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.uptime_buckets (owner, bucket_start, up, agent_silent, down, stuck, maintenance, unknown) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:20:00+00	0	0	0	0	0	60.001022937
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:25:00+00	0	60.000436817	0	0	0	239.99879179500002
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:45:00+00	0	0	282.421368518	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:00+00	0	299.99953434099996	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:30:00+00	119.99982717399999	0	120.000281262	0	0	60.0001953
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:35:00+00	0	0	299.99953434099996	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:50:00+00	240.00045739499998	0	0	59.99949192	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:40:00+00	0	300.000625798	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:40:00+00	0	0	300.000625798	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:45:00+00	0	282.421368518	0	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:00:00+00	240.00039387	0	0	0	0	59.999575065
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:00:00+00	240.00039387	0	0	0	0	59.999575065
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:00:00+00	240.00039387	0	0	0	0	59.999575065
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:00:00+00	240.00039387	0	0	0	0	59.999575065
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:05:00+00	59.999637371	0	0	0	0	269.76597252799996
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:00:00+00	240.00039387	0	0	0	0	59.999575065
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:00:00+00	240.00039387	0	0	0	0	59.999575065
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:00:00+00	240.00039387	0	0	0	0	59.999575065
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:05:00+00	59.999637371	0	0	0	0	269.76597252799996
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:05:00+00	59.999637371	0	0	0	0	269.76597252799996
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:05:00+00	59.999637371	0	0	0	0	269.76597252799996
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:05:00+00	59.999637371	0	0	0	0	269.76597252799996
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:05:00+00	59.999637371	0	0	0	0	269.76597252799996
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:05:00+00	59.999637371	0	0	0	0	269.76597252799996
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:10:00+00	60.000066364	0	0	0	0	59.999907252
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:10:00+00	60.000066364	0	0	0	0	59.999907252
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:10:00+00	60.000066364	0	0	0	0	59.999907252
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:10:00+00	60.000066364	0	0	0	0	59.999907252
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:10:00+00	60.000066364	0	0	0	0	59.999907252
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:10:00+00	60.000066364	0	0	0	0	59.999907252
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:10:00+00	60.000066364	0	0	0	0	59.999907252
\.


--
-- Data for Name: validators_cache; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.validators_cache (owner, operator, status, updated_at) FROM stdin;
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	0xf7ab920c3c19d225a9f6c2ee05599150f4d128f6	2	2026-11-25 16:05:44.300954+00
0x6dd6c111587b2124bbd315e451216dab566c609e	0xa6b2f6d6c03a21f62b6ebf41ad4dd0b7464861bf	2	2026-11-25 16:05:44.300954+00
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	0x379aa0d55f82c299be13f3daacdc6dbb080a3e6e	2	2026-11-25 16:05:44.300954+00
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	0x2d481c5cb134f362c39ee2034e754a1b801b6658	2	2026-11-25 16:05:44.300954+00
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	0x558d023212b40072f18de63e27adace57541b746	2	2026-11-25 16:05:44.300954+00
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	0x45899aec1488da1831ea65a879f62e460631284d	2	2026-11-25 16:05:44.300954+00
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	0x5bacebcfdad4d946b184276309a0b8b0a28ab608	2	2026-11-25 16:05:44.300954+00
\.


--
-- Name: alerts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.alerts_id_seq', 4, true);


--
-- Name: audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_log_id_seq', 7, true);


--
-- Name: deliveries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.deliveries_id_seq', 8, true);


--
-- Name: maintenance_windows_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.maintenance_windows_id_seq', 1, false);


--
-- Name: state_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.state_log_id_seq', 49, true);


--
-- PostgreSQL database dump complete
--

\unrestrict B4BiveSM9UxND6dFlVyPHhZkxU2zWvwj9qmvQdMfycOUzzleVtmWaVieJ7aPbAv

