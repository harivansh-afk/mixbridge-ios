#!/bin/bash

echo "Formatting Swift files..."
mint run swiftformat .

echo "Linting Swift files..."
mint run swiftlint
