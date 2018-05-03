# Development
## Build Gem
Run ```gem build fluent-plugin-application-insights.gemspec```.

## Run Test
Make sure you have bundler installed, you can install it by ```sudo gem install bundler```. And run ```bundler install``` once to install all dependencies.

Run ```rake test```.

## Release
If you are the current maintainer of this plugin:
1. Ensure all tests passed
2. Bump up version in ```fluent-plugin-application-insights.gemspec```
3. Build the gem, install it locally and test it
4. Create a PR with whatever changes needed before releasing, e.g., version bump up, documentation
5. Tag and push: ```git tag vx.xx.xx; git push --tags```
6. Create a github release with the pushed tag
7. Push to rubygems.org: ```gem push fluent-plugin-application-insights-<version>.gem```

# Contributing

This project welcomes contributions and suggestions. Most contributions require you to
agree to a Contributor License Agreement (CLA) declaring that you have the right to,
and actually do, grant us the rights to use your contribution. For details, visit
https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need
to provide a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the
instructions provided by the bot. You will only need to do this once across all repositories using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/)
or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.