implement Ffsdump;

include "sys.m";
	sys: Sys;
	print, sprint: import sys;
include "draw.m";
include "arg.m";
include "string.m";
	str: String;
include "util0.m";
	util: Util0;
	preadn, l2a, fail, warn, kill, killgrp, pid: import util;
include "../lib/ffs.m";
	ffs: Ffs;
	Disklabel, Dlpart, Super, Cg, Csum, Inode, Entry: import ffs;

Ffsdump: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};


dflag: int;
labeloff := big 0;
label := -1;

fd: ref Sys->FD;
time0: int;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	str = load String String->PATH;
	util = load Util0 Util0->PATH;
	util->init();
	ffs = load Ffs Ffs->PATH;
	ffs->init();

	sys->pctl(Sys->NEWPGRP, nil);

	arg->init(args);
	arg->setusage(arg->progname()+" [-d] [-l labelpart] part");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	ffs->dflag = dflag++;
		'l' =>	labelpart := arg->arg();
			if(len labelpart != 1)
				arg->usage();
			label = labelpart[0]-'a';
			if(label < 0)
				arg->usage();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();

	f := hd args;
	fd = sys->open(f, Sys->OREAD);
	if(fd == nil)
		fail(sprint("open: %r"));

	err: string;
	if(label >= 0) {
		dlp: ref Dlpart;
		(nil, dlp, labeloff, err) = Disklabel.get(fd, label);
		if(err != nil)
			fail(err);
		if(dlp.fstype != ffs->FSbsdffs)
			fail("not ffs");
	}

	s: ref Super;
	(s, err) = Super.read(fd, labeloff+ffs->Superoff);
	if(err != nil)
		fail(sprint("parsing super: %r"));
	print("%s", s.text());

	cgoff := labeloff+big s.fragsize*big s.offcyl;
	warn(sprint("reading first cylinder group at offset %#bx", cgoff));
	cg: ref Cg;
	(cg, err) = Cg.read(fd, s.blocksize, cgoff);
	if(err != nil)
		fail("parsing cylinder group: "+err);
	print("\n%s", cg.text());

	root: ref Inode;
	rootoff := labeloff+big (s.offinode*s.fragsize)+big (ffs->Rootinode*ffs->Inodelen);
	(root, err) = Inode.read(fd, rootoff, s);
	if(err != nil)
		fail(err);
	print("\n%s", root.text());

	ibuf := array[int root.length] of byte;
	n := ffs->inodereadn(fd, labeloff, s.fragsize, root, ibuf, len ibuf, big 0);
	if(n != len ibuf)
		fail(sprint("short read for root directory: %r"));

	print("root directory:\n");
	e: ref Entry;
	io := 0;
	while(io < len ibuf) {
		(e, io, err) = Entry.parse(ibuf, io);
		if(err != nil)
			fail(err);
		print("\t%s\n", e.text());
	}
}

say(s: string)
{
	if(dflag)
		warn(s);
}
