--
-- PostgreSQL database dump
--

\restrict 5GPq0MKdapdveCvi0z5uSj42Fhfbmgl0C8wackBRJdV1Y0vTVJTKWuR0HUSNHb6

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
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	0x379aa0d55f82c299be13f3daacdc6dbb080a3e6e	b4038b4e2170f07fc9f09e09239d6ff55104bb3aa6891182bb746a410543505f19729590925cae92221c58e576c0d2193376fa23b7d64d67614b5d8cd588d951	0x1eadee8d475f4a3d79a86f508130935d799f45ec	2026-11-25 16:45:42.65101+00	\N	33
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	0x2d481c5cb134f362c39ee2034e754a1b801b6658	16a9c965eb9358f58a5944dd5267cb822de2318b102d46985d0a14b950c4e38162586253bed0b273f66249d617c3c0304f60dc0957e4a1776c76cf7c77cd0d20	0x69193e96d016ec0f44b6f4135186f8be4da8f9f7	2026-11-25 16:46:02.542091+00	\N	16
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	0x45899aec1488da1831ea65a879f62e460631284d	422b169fb08dc88fd5206670de64207a33cbcdb3619486d3f9536c68f72a09945173fcfd107dd2966aeb5b9f6a8e2003b3e64e48bc857303db2f5c8f235266cf	0xed0fbd15a6a543cd37e9c1a3259d7b1e28b723c5	2026-11-25 16:45:49.82422+00	\N	33
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	0x558d023212b40072f18de63e27adace57541b746	afb47d76d2e2ec3226c49f27fb7dbe8390b6a7197cd31f059c8edce9b14af470a3d96a56a7ee3d943e40e517bf5d3ea4ffec90dbdc0a49cd61e5cfcfbd34b777	0x7f364f8bf69286bce3a30c2af8ef867be356ab88	2026-11-25 16:45:56.560816+00	\N	33
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	0xf7ab920c3c19d225a9f6c2ee05599150f4d128f6	6a63fd39eae71f791ca03ddf0ff7c7f675177b28cc80f0fd0ba8ec30a122bfc070f161fb297305f4ae9685d47fec8133e49af6747866651a26d4977a6c8fd29d	0x35f11df5db3a7ffe1aea07c342a01f724601c4fc	2026-11-25 16:46:09.441344+00	\N	33
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	0x5bacebcfdad4d946b184276309a0b8b0a28ab608	2ee39b7b2596c0c76fb2ea87086e4c58a289cfd0289c916db47eaec04e1f4c8db14f441259e9be70e44b0ce2e24ba2f808884be2b0d700384f655b5460062614	0x5fe939ea276e40f3d6fc2e1c6a6c28fe3a03ed74	2026-11-25 16:46:15.865809+00	\N	33
0x6dd6c111587b2124bbd315e451216dab566c609e	0xa6b2f6d6c03a21f62b6ebf41ad4dd0b7464861bf	77fc693461750f739b225c9745e8741139ea836b7ae9d8d3938b90edbef9006ceb8665b5373815e794387b4767d68d03288d166ad1f1e9c040e673d732ce88eb	0xdfb1b9d242c4ca89acfa276298c03c81214ae01d	2026-11-25 16:46:21.744603+00	\N	33
\.


--
-- Data for Name: alerts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.alerts (id, episode_id, type, owner, started_at, created_at, broad, rules_version) FROM stdin;
1	d0cb6552-1795625393	NODE_DOWN	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:49:53.810236+00	2026-11-25 16:59:53.810589+00	f	watch-rules-v1
2	cc7185d2-1795625513	AGENT_SILENT	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:51:53.810398+00	2026-11-25 17:02:53.81053+00	f	watch-rules-v1
3	cc7185d2-1795625513	RECOVERED	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:51:53.810398+00	2026-11-25 17:09:37.865909+00	f	watch-rules-v1
4	d0cb6552-1795625393	RECOVERED	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:49:53.810236+00	2026-11-25 17:11:37.866105+00	f	watch-rules-v1
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_log (id, at, actor, action, detail, prev_hash, hash) FROM stdin;
1	2026-11-25 16:45:42.65101+00	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	register_agent	agent 0x1eadee8d475f4a3d79a86f508130935d799f45ec		5002de5e249494251723e0fd265613bf03d1da89d6eda8e8e0852684050dab74
2	2026-11-25 16:47:58.520212+00	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	set_manager	from 0x to 0xf8a1…3577	5002de5e249494251723e0fd265613bf03d1da89d6eda8e8e0852684050dab74	ad11e7492a266f7840c70da35afe59acfed1e99af53e361d36c6f216711ca44c
3	2026-11-25 16:48:07.250102+00	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	set_manager	from 0xf8a1…3577 to 0xf8a1…3577	ad11e7492a266f7840c70da35afe59acfed1e99af53e361d36c6f216711ca44c	294c9a53eb2b680159cc3dc3d215c66c60ed411f0d34f1d5e8a23226451bf1f8
4	2026-11-25 17:18:00.365269+00	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	read_contacts	7 validators	294c9a53eb2b680159cc3dc3d215c66c60ed411f0d34f1d5e8a23226451bf1f8	1de138133e9c6d2580255ce05744eb5acc9c8b857abd02d6516d673f7b8bbd93
5	2026-11-25 17:18:20.437626+00	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	read_contacts	7 validators	1de138133e9c6d2580255ce05744eb5acc9c8b857abd02d6516d673f7b8bbd93	d263fae86b54bbe4f893028cbb2bb2a1bbaacb2ee74e9a6f591a0e38f24ec68a
\.


--
-- Data for Name: check_results; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.check_results (owner, at, state, code, signals, rules_version) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:39:53.809975+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:40:53.809877+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:41:53.809957+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:42:53.81021+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:43:53.812117+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:44:53.809993+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:44:53.809993+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:44:53.809993+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:44:53.809993+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:44:53.809993+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:44:53.809993+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:44:53.809993+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:45:53.81074+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:45:53.81074+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:45:53.81074+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:45:53.81074+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:45:53.81074+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:45:53.81074+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:45:53.81074+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:46:53.810742+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:46:53.810742+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:46:53.810742+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:46:53.810742+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:46:53.810742+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:46:53.810742+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 27}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:46:53.810742+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:47:53.810191+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:47:53.810191+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:47:53.810191+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:47:53.810191+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:47:53.810191+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:47:53.810191+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 27}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:47:53.810191+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:48:53.810625+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:48:53.810625+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:48:53.810625+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:48:53.810625+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:48:53.810625+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:48:53.810625+00	UNKNOWN	P2P_UNSEEN	{"s1": true, "s2": true, "s3": {"mon": false}, "lag": 17}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:48:53.810625+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:49:53.810236+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:49:53.810236+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:49:53.810236+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:49:53.810236+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:49:53.810236+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 32}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:49:53.810236+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 330}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:49:53.810236+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:50:53.810522+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:50:53.810522+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:50:53.810522+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:50:53.810522+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:50:53.810522+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 49}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:50:53.810522+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 347}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:50:53.810522+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:51:53.810398+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:51:53.810398+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:51:53.810398+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:51:53.810398+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:51:53.810398+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:51:53.810398+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 362}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:51:53.810398+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:52:53.810048+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:52:53.810048+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:52:53.810048+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:52:53.810048+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:52:53.810048+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:52:53.810048+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 378}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:52:53.810048+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:53:53.810266+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:53:53.810266+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:53:53.810266+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 9}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:53:53.810266+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:53:53.810266+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:53:53.810266+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 396}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:53:53.810266+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:54:53.810636+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:54:53.810636+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:54:53.810636+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:54:53.810636+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:54:53.810636+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:54:53.810636+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 412}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:54:53.810636+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:55:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:55:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:55:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:55:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:55:53.81053+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:55:53.81053+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 427}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:55:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:56:53.810845+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 9}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:56:53.810845+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:56:53.810845+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:56:53.810845+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:56:53.810845+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:56:53.810845+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 444}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:56:53.810845+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:58:53.810628+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 9}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:58:53.810628+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:58:53.810628+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 9}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:58:53.810628+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:58:53.810628+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:58:53.810628+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 477}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:58:53.810628+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:57:53.810254+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:57:53.810254+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:57:53.810254+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:57:53.810254+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:57:53.810254+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:57:53.810254+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 462}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:57:53.810254+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:59:53.810589+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:59:53.810589+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:59:53.810589+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:59:53.810589+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:59:53.810589+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:59:53.810589+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 492}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:59:53.810589+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:00:53.810643+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:00:53.810643+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:00:53.810643+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:00:53.810643+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:00:53.810643+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:00:53.810643+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 510}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:00:53.810643+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:01:53.810284+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:01:53.810284+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:01:53.810284+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:01:53.810284+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:01:53.810284+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:01:53.810284+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 527}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:01:53.810284+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:02:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:02:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:02:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:02:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:02:53.81053+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:02:53.81053+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 542}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:02:53.81053+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:04:37.865915+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:04:37.865915+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:04:37.865915+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:04:37.865915+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:04:37.865915+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:04:37.865915+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 570}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:04:37.865915+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:05:37.865349+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:05:37.865349+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:05:37.865349+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:05:37.865349+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:05:37.865349+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:05:37.865349+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 588}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:05:37.865349+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:07:37.865946+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:07:37.865946+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:07:37.865946+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:07:37.865946+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 26}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:07:37.865946+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:07:37.865946+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 19}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:07:37.865946+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 23}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:06:37.865864+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:06:37.865864+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 9}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:06:37.865864+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:06:37.865864+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:06:37.865864+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:06:37.865864+00	NODE_STUCK		{"s1": true, "s2": false, "s3": {"mon": true}, "lag": 605}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:06:37.865864+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:08:37.866302+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:08:37.866302+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:08:37.866302+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:08:37.866302+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 26}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:08:37.866302+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:08:37.866302+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 20}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:08:37.866302+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 23}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:09:37.865909+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:09:37.865909+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:09:37.865909+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:09:37.865909+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 26}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:09:37.865909+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:09:37.865909+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 20}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:09:37.865909+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 23}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:10:37.865594+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:10:37.865594+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:10:37.865594+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:10:37.865594+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 26}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:10:37.865594+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:10:37.865594+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 20}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:10:37.865594+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 23}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:11:37.866105+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:11:37.866105+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:11:37.866105+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:11:37.866105+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 26}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:11:37.866105+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:11:37.866105+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 20}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:11:37.866105+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 23}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:12:37.865781+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:12:37.865781+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:12:37.865781+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:12:37.865781+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:12:37.865781+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:12:37.865781+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:12:37.865781+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:13:37.866198+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:13:37.866198+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:13:37.866198+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:13:37.866198+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:13:37.866198+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:13:37.866198+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:13:37.866198+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:15:37.865536+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:15:37.865536+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:15:37.865536+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:15:37.865536+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:15:37.865536+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:15:37.865536+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:15:37.865536+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:17:37.865421+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:17:37.865421+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:17:37.865421+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:17:37.865421+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:17:37.865421+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:17:37.865421+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:17:37.865421+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:14:37.866169+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:14:37.866169+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:14:37.866169+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:14:37.866169+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:14:37.866169+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:14:37.866169+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:14:37.866169+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:16:37.866254+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:16:37.866254+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:16:37.866254+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:16:37.866254+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:16:37.866254+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:16:37.866254+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:16:37.866254+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
\.


--
-- Data for Name: contacts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.contacts (owner, channel, value, state, verified_at, fail_count, updated_at) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	telegram	wjd21AgqJ+n1hnVFLs/lHhtFwv4FX+ip78wQtzXbBaw=	verified	2026-11-25 16:47:26.819329+00	0	2026-11-25 16:47:26.819329+00
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	telegram	sVn6xEy6yxFR1NELOzBW6Z30UF7Qn9tsKcRWWmmxozo=	verified	2026-11-25 16:47:44.290534+00	0	2026-11-25 17:09:52.816917+00
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	telegram	l+Ojhda+AO5kyLdv8sopQ92Iwgw+fnu0qP+EjE5tp3k=	verified	2026-11-25 16:47:38.058242+00	0	2026-11-25 17:11:52.823832+00
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	telegram	nGAX+Nl5sbm5HlbKHKXffC98/jAaY89D+j09rMGNEDI=	verified	2026-11-25 16:47:32.63886+00	0	2026-11-25 17:11:52.827696+00
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	email	klVDiFj3Yhj8E1nG47W5WHb8SEfoJUrrOw4n5PPUBk8tJ6SL2V0+q3EXkHw=	verified	2026-11-25 16:47:50.217251+00	0	2026-11-25 17:11:52.829067+00
\.


--
-- Data for Name: cursors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cursors (key, value) FROM stdin;
poll_offset_telegram	104
registry_scan_block	666
notifier_alert_id	4
notifier_undeliverable_alert_id	2
\.


--
-- Data for Name: deliveries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.deliveries (id, alert_id, episode_id, kind, recipient, role, channel, state, attempts, next_at, last_error, body, created_at, sent_at) FROM stdin;
2	1	d0cb6552-1795625393	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	telegram	sent	1	2026-11-25 17:00:08.633349+00		🔴 نود ولیدیتور از ۱۰ دقیقه پیش در دسترس نیست\nولیدیتور: 0xd0cb…1dd2   وضعیت: NODE_DOWN\nآخرین ضربان: ۲۰:۳۰\nآپ‌تایم ۲۴ ساعت: ۱۵٫۴٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 17:00:08.63335+00	2026-11-25 17:00:08.638444+00
3	1	d0cb6552-1795625393	alert	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	manager	telegram	sent	1	2026-11-25 17:00:08.634649+00		🔴 نود ولیدیتور از ۱۰ دقیقه پیش در دسترس نیست\nولیدیتور: 0xd0cb…1dd2   وضعیت: NODE_DOWN\nآخرین ضربان: ۲۰:۳۰\nآپ‌تایم ۲۴ ساعت: ۱۵٫۴٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 17:00:08.634649+00	2026-11-25 17:00:08.647072+00
1	1	d0cb6552-1795625393	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	email	sent	1	2026-11-25 17:00:08.631569+00		🔴 نود ولیدیتور از ۱۰ دقیقه پیش در دسترس نیست\nولیدیتور: 0xd0cb…1dd2   وضعیت: NODE_DOWN\nآخرین ضربان: ۲۰:۳۰\nآپ‌تایم ۲۴ ساعت: ۱۵٫۴٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 17:00:08.631569+00	2026-11-25 17:00:08.652327+00
4	2	cc7185d2-1795625513	alert	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	owner	telegram	sent	1	2026-11-25 17:03:08.629069+00		🟡 ایجنت ولیدیتور ۱۱ دقیقه است ضربان نمی‌فرستد (نود در شبکه دیده می‌شود)\nولیدیتور: 0xcc71…28d0   وضعیت: AGENT_SILENT\nآخرین ضربان: ۲۰:۱۸   آخرین ارتفاع دیده‌شده: ۲۹۸\nآپ‌تایم ۲۴ ساعت: ۱۰۰٫۰٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 17:03:08.629069+00	2026-11-25 17:03:08.634123+00
5	3	cc7185d2-1795625513	alert	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	owner	telegram	sent	1	2026-11-25 17:09:52.81502+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۱۸ دقیقه)\nولیدیتور: 0xcc71…28d0   وضعیت: UP\nآخرین ضربان: ۲۰:۳۹   آخرین ارتفاع دیده‌شده: ۷۰۱\nآپ‌تایم ۲۴ ساعت: ۱۰۰٫۰٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 17:09:52.81502+00	2026-11-25 17:09:52.816917+00
7	4	d0cb6552-1795625393	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	telegram	sent	1	2026-11-25 17:11:52.817004+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۲۲ دقیقه)\nولیدیتور: 0xd0cb…1dd2   وضعیت: UP\nآخرین ضربان: ۲۰:۴۰   آخرین ارتفاع دیده‌شده: ۷۳۵\nآپ‌تایم ۲۴ ساعت: ۲۸٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 17:11:52.817004+00	2026-11-25 17:11:52.823832+00
8	4	d0cb6552-1795625393	alert	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	manager	telegram	sent	1	2026-11-25 17:11:52.818991+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۲۲ دقیقه)\nولیدیتور: 0xd0cb…1dd2   وضعیت: UP\nآخرین ضربان: ۲۰:۴۰   آخرین ارتفاع دیده‌شده: ۷۳۵\nآپ‌تایم ۲۴ ساعت: ۲۸٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 17:11:52.818992+00	2026-11-25 17:11:52.827696+00
6	4	d0cb6552-1795625393	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	email	sent	1	2026-11-25 17:11:52.816363+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۲۲ دقیقه)\nولیدیتور: 0xd0cb…1dd2   وضعیت: UP\nآخرین ضربان: ۲۰:۴۰   آخرین ارتفاع دیده‌شده: ۷۳۵\nآپ‌تایم ۲۴ ساعت: ۲۸٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 17:11:52.816363+00	2026-11-25 17:11:52.829067+00
\.


--
-- Data for Name: engine_state; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.engine_state (owner, payload) FROM stdin;
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	{"Code": "", "Sent": null, "Owner": "0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2", "Since": "2026-11-25T17:17:37.86542179Z", "State": "UP", "UpSince": "2026-11-25T17:17:37.86542179Z", "LastTick": "2026-11-25T17:17:37.86542179Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	{"Code": "", "Sent": null, "Owner": "0xf8a13c5a99e617cb22eb184d14266de4b82d3577", "Since": "2026-11-25T17:17:37.86542179Z", "State": "UP", "UpSince": "2026-11-25T17:17:37.86542179Z", "LastTick": "2026-11-25T17:17:37.86542179Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	{"Code": "", "Sent": null, "Owner": "0x10e3f7133f3fc58a30b17ae57846278dbab4044f", "Since": "2026-11-25T17:17:37.86542179Z", "State": "UP", "UpSince": "2026-11-25T17:17:37.86542179Z", "LastTick": "2026-11-25T17:17:37.86542179Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	{"Code": "", "Sent": null, "Owner": "0x3481a641697c8706d924ede2fa2ed7fd40b25e9c", "Since": "2026-11-25T17:17:37.86542179Z", "State": "UP", "UpSince": "2026-11-25T17:17:37.86542179Z", "LastTick": "2026-11-25T17:17:37.86542179Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0x6dd6c111587b2124bbd315e451216dab566c609e	{"Code": "", "Sent": null, "Owner": "0x6dd6c111587b2124bbd315e451216dab566c609e", "Since": "2026-11-25T17:17:37.86542179Z", "State": "UP", "UpSince": "2026-11-25T17:17:37.86542179Z", "LastTick": "2026-11-25T17:17:37.86542179Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	{"Code": "", "Sent": null, "Owner": "0xb0b3fff6193b77c818f3b7733e1966d60cf8239e", "Since": "2026-11-25T17:17:37.86542179Z", "State": "UP", "UpSince": "2026-11-25T17:17:37.86542179Z", "LastTick": "2026-11-25T17:17:37.86542179Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	{"Code": "", "Sent": null, "Owner": "0xcc7185d2082e647e2d3643596d626ab2f8f028d0", "Since": "2026-11-25T17:17:37.86542179Z", "State": "UP", "UpSince": "2026-11-25T17:17:37.86542179Z", "LastTick": "2026-11-25T17:17:37.86542179Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
\.


--
-- Data for Name: heartbeats_latest; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.heartbeats_latest (owner, recv_at, head_changed_at, payload) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:17:45.943652+00	2026-11-25 17:17:45.943652+00	{"v": 1, "ts": 1795627065, "seq": 33, "owner": "0xb0b3fff6193b77c818f3b7733e1966d60cf8239e", "peers": 7, "nodeId": "b4038b4e2170f07fc9f09e09239d6ff55104bb3aa6891182bb746a410543505f19729590925cae92221c58e576c0d2193376fa23b7d64d67614b5d8cd588d951", "rpc_ok": true, "rtt_ms": 3, "chainId": 262025, "cpu_pct": 31, "mem_pct": 41, "syncing": false, "operator": "0x379aa0d55f82c299be13f3daacdc6dbb080a3e6e", "head_hash": "0x6e6b0ac4ed1caa5a8f4f81be2627914cd961d8a3d1c5f21a138963a923048907", "load_x100": 269, "head_number": 939, "agentVersion": "0.1.0", "disk_free_pct": 83, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 952}
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:18:24.016719+00	2026-11-25 17:18:24.016719+00	{"v": 1, "ts": 1795627104, "seq": 33, "owner": "0x6dd6c111587b2124bbd315e451216dab566c609e", "peers": 7, "nodeId": "77fc693461750f739b225c9745e8741139ea836b7ae9d8d3938b90edbef9006ceb8665b5373815e794387b4767d68d03288d166ad1f1e9c040e673d732ce88eb", "rpc_ok": true, "rtt_ms": 2, "chainId": 262025, "cpu_pct": 33, "mem_pct": 42, "syncing": false, "operator": "0xa6b2f6d6c03a21f62b6ebf41ad4dd0b7464861bf", "head_hash": "0xa62ff6803330a9eaffa49d5801b7ea32b4bf61bf9fabd13bb63bb626adb79dad", "load_x100": 280, "head_number": 958, "agentVersion": "0.1.0", "disk_free_pct": 83, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 972}
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:17:52.500719+00	2026-11-25 17:17:52.500719+00	{"v": 1, "ts": 1795627072, "seq": 33, "owner": "0xf8a13c5a99e617cb22eb184d14266de4b82d3577", "peers": 7, "nodeId": "422b169fb08dc88fd5206670de64207a33cbcdb3619486d3f9536c68f72a09945173fcfd107dd2966aeb5b9f6a8e2003b3e64e48bc857303db2f5c8f235266cf", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 33, "mem_pct": 42, "syncing": false, "operator": "0x45899aec1488da1831ea65a879f62e460631284d", "head_hash": "0x397f53b742a42bdb7beabfc791da764844596d8ec5df04cf95d878a9eae25157", "load_x100": 280, "head_number": 942, "agentVersion": "0.1.0", "disk_free_pct": 83, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 482}
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:18:12.026308+00	2026-11-25 17:18:12.026308+00	{"v": 1, "ts": 1795627092, "seq": 33, "owner": "0x3481a641697c8706d924ede2fa2ed7fd40b25e9c", "peers": 7, "nodeId": "6a63fd39eae71f791ca03ddf0ff7c7f675177b28cc80f0fd0ba8ec30a122bfc070f161fb297305f4ae9685d47fec8133e49af6747866651a26d4977a6c8fd29d", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 35, "mem_pct": 42, "syncing": false, "operator": "0xf7ab920c3c19d225a9f6c2ee05599150f4d128f6", "head_hash": "0x8e4220b13ae6d0d8a3095de5dc4073554447e1c4a0a101505736be5320b391fb", "load_x100": 284, "head_number": 952, "agentVersion": "0.1.0", "disk_free_pct": 83, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 981}
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:17:49.603887+00	2026-11-25 17:17:49.603887+00	{"v": 1, "ts": 1795627069, "seq": 16, "owner": "0xcc7185d2082e647e2d3643596d626ab2f8f028d0", "peers": 7, "nodeId": "16a9c965eb9358f58a5944dd5267cb822de2318b102d46985d0a14b950c4e38162586253bed0b273f66249d617c3c0304f60dc0957e4a1776c76cf7c77cd0d20", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 33, "mem_pct": 41, "syncing": false, "operator": "0x2d481c5cb134f362c39ee2034e754a1b801b6658", "head_hash": "0x62a553d9b50bdcdec5fcd1d824ea07620db6d37458c61e9fbcd1da4a60525863", "load_x100": 280, "head_number": 941, "agentVersion": "0.1.0", "disk_free_pct": 83, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 644}
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:17:58.717333+00	2026-11-25 17:17:58.717333+00	{"v": 1, "ts": 1795627078, "seq": 33, "owner": "0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2", "peers": 7, "nodeId": "afb47d76d2e2ec3226c49f27fb7dbe8390b6a7197cd31f059c8edce9b14af470a3d96a56a7ee3d943e40e517bf5d3ea4ffec90dbdc0a49cd61e5cfcfbd34b777", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 34, "mem_pct": 41, "syncing": false, "operator": "0x558d023212b40072f18de63e27adace57541b746", "head_hash": "0x67413127b2a5f2212a70af6bc9756f6ace4f1b430e9874212833de3bd7207ab0", "load_x100": 300, "head_number": 945, "agentVersion": "0.1.0", "disk_free_pct": 83, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 738}
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:18:18.273046+00	2026-11-25 17:18:18.273046+00	{"v": 1, "ts": 1795627098, "seq": 33, "owner": "0x10e3f7133f3fc58a30b17ae57846278dbab4044f", "peers": 7, "nodeId": "2ee39b7b2596c0c76fb2ea87086e4c58a289cfd0289c916db47eaec04e1f4c8db14f441259e9be70e44b0ce2e24ba2f808884be2b0d700384f655b5460062614", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 34, "mem_pct": 41, "syncing": false, "operator": "0x5bacebcfdad4d946b184276309a0b8b0a28ab608", "head_hash": "0x275f8056f920fad068056ab643bb1df3f13afaead81363b4c333137a5427821d", "load_x100": 278, "head_number": 955, "agentVersion": "0.1.0", "disk_free_pct": 83, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 239}
\.


--
-- Data for Name: link_codes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.link_codes (code_hash, owner, channel, value, expires_at, used_at) FROM stdin;
2fadea0bed19244678caa02cb0222143082b3a5e60efcb6e43e595e8f1ef18ff	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	telegram		2026-11-25 16:57:26.770488+00	2026-11-25 16:47:26.818693+00
da4fe81456d5db9353dc1cff1429b99b6618830571b513e606e44a75d1b285f2	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	telegram		2026-11-25 16:57:32.541618+00	2026-11-25 16:47:32.638484+00
abdcec2fd978824ce620b20234b6c2b91534455f9b0d296a7bbd6beffc2d7c97	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	telegram		2026-11-25 16:57:37.920938+00	2026-11-25 16:47:38.05773+00
d464dcd5690b27a8e79dc17ac72bbb18d3bafedf87403e12187fffd82132a3e8	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	telegram		2026-11-25 16:57:44.135172+00	2026-11-25 16:47:44.290222+00
31ffa961aab897a3b0222a4c119bfa104c2f663ed25d6d59bf1e16c422920397	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	email	klVDiFj3Yhj8E1nG47W5WHb8SEfoJUrrOw4n5PPUBk8tJ6SL2V0+q3EXkHw=	2026-11-25 16:57:50.207981+00	2026-11-25 16:47:50.216848+00
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
1	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:39:53.809975+00		UNKNOWN	NOT_REGISTERED	
2	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:44:53.809993+00		UNKNOWN	NOT_REGISTERED	
3	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:44:53.809993+00		UNKNOWN	NOT_REGISTERED	
4	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:44:53.809993+00		UNKNOWN	NOT_REGISTERED	
5	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:44:53.809993+00		UNKNOWN	NOT_REGISTERED	
6	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:44:53.809993+00		UNKNOWN	NOT_REGISTERED	
7	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:44:53.809993+00		UNKNOWN	NOT_REGISTERED	
8	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:45:53.81074+00	UNKNOWN	UP		
9	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:45:53.81074+00	UNKNOWN	UP		
10	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:46:53.810742+00	UNKNOWN	UP		
11	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:46:53.810742+00	UNKNOWN	UP		
12	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:46:53.810742+00	UNKNOWN	UP		
13	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:46:53.810742+00	UNKNOWN	UP		
14	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:46:53.810742+00	UNKNOWN	UP		
15	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:48:53.810625+00	UP	UNKNOWN	P2P_UNSEEN	
16	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:49:53.810236+00	UNKNOWN	NODE_DOWN		
17	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:51:53.810398+00	UP	AGENT_SILENT		
18	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:06:37.865864+00	AGENT_SILENT	UP		cc7185d2-1795625513
19	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:06:37.865864+00	NODE_DOWN	NODE_STUCK		d0cb6552-1795625393
20	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:07:37.865946+00	NODE_STUCK	UP		d0cb6552-1795625393
21	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:12:37.865781+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
22	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:12:37.865781+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
23	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:12:37.865781+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
24	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:12:37.865781+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
25	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:12:37.865781+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
26	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:12:37.865781+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
27	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:12:37.865781+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
28	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:17:37.865421+00	UNKNOWN	UP		
29	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:17:37.865421+00	UNKNOWN	UP		
30	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:17:37.865421+00	UNKNOWN	UP		
31	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:17:37.865421+00	UNKNOWN	UP		
32	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:17:37.865421+00	UNKNOWN	UP		
33	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:17:37.865421+00	UNKNOWN	UP		
34	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:17:37.865421+00	UNKNOWN	UP		
\.


--
-- Data for Name: uptime_buckets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.uptime_buckets (owner, bucket_start, up, agent_silent, down, stuck, maintenance, unknown) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:10:00+00	120.000195796	0	0	0	0	180.000063993
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:00:00+00	284.055326079	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:00:00+00	284.055326079	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:40:00+00	0	0	0	0	0	300.00001809500003
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:00:00+00	284.055326079	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:00:00+00	284.055326079	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:00:00+00	0	284.055326079	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:55:00+00	299.999953262	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:55:00+00	299.999953262	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:55:00+00	299.999953262	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:55:00+00	299.999953262	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:55:00+00	0	299.999953262	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:55:00+00	0	0	299.999953262	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:50:00+00	300.000399403	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:50:00+00	300.000399403	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:50:00+00	300.000399403	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:50:00+00	300.000399403	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:50:00+00	60.000285711	240.00011369199999	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:50:00+00	0	0	300.000399403	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:50:00+00	300.000399403	0	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:45:00+00	239.99949598199998	0	0	0	0	60.000747007
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:45:00+00	239.99949598199998	0	0	0	0	60.000747007
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:45:00+00	239.99949598199998	0	0	0	0	60.000747007
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:45:00+00	300.000242989	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:45:00+00	239.99949598199998	0	0	0	0	60.000747007
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:45:00+00	119.999450216	0	59.999610817	0	0	120.00118195600001
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:45:00+00	300.000242989	0	0	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:55:00+00	299.999953262	0	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:00:00+00	0	0	284.055326079	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:00:00+00	284.055326079	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:10:00+00	120.000195796	0	0	0	0	180.000063993
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:10:00+00	120.000195796	0	0	0	0	180.000063993
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:10:00+00	120.000195796	0	0	0	0	180.000063993
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:05:00+00	299.999994118	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:05:00+00	299.999994118	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:15:00+00	59.999167739	0	0	0	0	120.00008459700001
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:15:00+00	59.999167739	0	0	0	0	120.00008459700001
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:15:00+00	59.999167739	0	0	0	0	120.00008459700001
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:10:00+00	120.000195796	0	0	0	0	180.000063993
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:05:00+00	299.999994118	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:05:00+00	299.999994118	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 17:05:00+00	240.00055997599998	59.999434142	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 17:05:00+00	180.000045528	0	59.999434142	60.000514448	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 17:05:00+00	299.999994118	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:10:00+00	120.000195796	0	0	0	0	180.000063993
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:10:00+00	120.000195796	0	0	0	0	180.000063993
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 17:15:00+00	59.999167739	0	0	0	0	120.00008459700001
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 17:15:00+00	59.999167739	0	0	0	0	120.00008459700001
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 17:15:00+00	59.999167739	0	0	0	0	120.00008459700001
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 17:15:00+00	59.999167739	0	0	0	0	120.00008459700001
\.


--
-- Data for Name: validators_cache; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.validators_cache (owner, operator, status, updated_at) FROM stdin;
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	0x5bacebcfdad4d946b184276309a0b8b0a28ab608	2	2026-11-25 17:08:37.907303+00
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	0xf7ab920c3c19d225a9f6c2ee05599150f4d128f6	2	2026-11-25 17:08:37.907303+00
0x6dd6c111587b2124bbd315e451216dab566c609e	0xa6b2f6d6c03a21f62b6ebf41ad4dd0b7464861bf	2	2026-11-25 17:08:37.907303+00
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	0x379aa0d55f82c299be13f3daacdc6dbb080a3e6e	2	2026-11-25 17:08:37.907303+00
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	0x2d481c5cb134f362c39ee2034e754a1b801b6658	2	2026-11-25 17:08:37.907303+00
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	0x558d023212b40072f18de63e27adace57541b746	2	2026-11-25 17:08:37.907303+00
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	0x45899aec1488da1831ea65a879f62e460631284d	2	2026-11-25 17:08:37.907303+00
\.


--
-- Name: alerts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.alerts_id_seq', 4, true);


--
-- Name: audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_log_id_seq', 5, true);


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

SELECT pg_catalog.setval('public.state_log_id_seq', 34, true);


--
-- PostgreSQL database dump complete
--

\unrestrict 5GPq0MKdapdveCvi0z5uSj42Fhfbmgl0C8wackBRJdV1Y0vTVJTKWuR0HUSNHb6

