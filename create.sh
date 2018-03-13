#!/bin/sh

#  create.sh
#  WebCrawler
#
#  Created by Harry Wright on 08/03/2018.
#  

echo "Building WebCrawler"
swift build -c release -Xswiftc -static-stdlib

echo "Regenerating xcodeproj"
swift package generate-xcodeproj

echo "Copying newly built copy to /usr/..."
cd .build/release
cp -f WebCrawler /usr/local/bin/webcrawler

echo "Finished\n"
echo "To use WebCrawler, please enter:\n\t webcrawler --url <url>"
