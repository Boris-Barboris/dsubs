@echo off
rdmd --build-only -c -Isource -Dddocs_tmp -X -Xfdocs/docs.json -version=MySQLDocs --force source/mysql/package.d
rmdir /S /Q docs_tmp > NUL 2> NUL
del source\mysql\package.obj

echo Building ddox...
cd .\ddox
dub build
cd ..
echo Done building ddox...

echo ddox filter...
.\ddox\ddox -- filter docs/docs.json --min-protection Public
echo ddox generate-html...
.\ddox\ddox -- generate-html docs/docs.json docs/public --navigation-type=ModuleTree --override-macros=ddoc/macros.ddoc --override-macros=ddoc/packageVersion.ddoc
