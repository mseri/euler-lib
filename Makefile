# This option is intended to be used from opam.
DUNE_BUILD_OPTIONS ?=

default: all

all: lib doc test

lib:
	dune build $(DUNE_BUILD_OPTIONS)
	@# We would like not to expose internal modules (hackish!!).
	@# For this to work, internal modules PE__* must be shipped in the archive
	@# file of the library. Otherwise, any internal reference to module PE__Foo
	@# (either the exposed module PE.Foo being an alias to PE__Foo, or another
	@# module PE__Bar using a value from PE__Foo) will require the PE__Foo.cm*
	@# files, or will result in an “unbound module PE__Foo” error.
	@# There are two methods which seem to achieve this.
	@#   — Either PE.Foo is an alias to PE__Foo; in this case, its interface
	@#     must hide that fact, otherwise the produced archive file simply
	@#     refers to module PE__Foo without shipping it itself.
	@#   — Or, PE.Foo includes PE__Foo (in the sense of module inclusion); in
	@#     this case, it seems that the produced archive file ships PE__Foo.
	@# There should be a way to do this from dune…
	@# In fact, we HAVE to provide *.cmi and .cmti files of internal modules, so
	@# that odoc (through odig) can build the HTML documentation!
	@# Moreover, *.cmt files are required for Merlin the documentation of the
	@# library (command :MerlinDocument in Vim).
	@rm _build/install/default/lib/pe/PE__*.cm[ox]
	@rm _build/install/default/lib/pe/PE.cm[ox]
	@sed '/{"PE__.*\.cm[ox]"}/d' -i _build/default/pe.install
	@sed '/{"PE\.cm[ox]"}/d'     -i _build/default/pe.install
	@cp _build/default/pe.install pe.install

doc:
	dune build @doc
	@# We replace odoc theme with ocamldoc theme (hackish!):
	@cp ocamldoc-style.css _build/default/_doc/_html/odoc.css

test:
	@echo -e '\e[1;41mTODO\e[0m use a test tool!'
	@false

clean:
	dune clean

install: lib
	ocamlfind remove pe
	dune install

# example Makefile for dune:
#     https://github.com/c-cube/ocaml-containers/raw/master/Makefile
