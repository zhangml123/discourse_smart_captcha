#### Smart captcha plugin for Discourse / Discourse 智能验证码插件
##### 适用discourse版本 discourse version v2.5.0.beta2  commit f8ec5f309a80ef34776eacaac951c398693caa69
##### docker 安装方式
1、配置`app.yml` 
```
    hooks:
      after_code:
        - exec:
            cd: $home/plugins
            cmd:
              - mkdir -p plugins
              - git clone https://github.com/discourse/docker_manager.git
              - git clone https://github.com/zhangml123/discourse_smart_captcha.git
```
2、重构容器
```
$ ./launcher rebuild app
```
##### 容器内安装方式
1、进入容器
```
$ sudo docker exec -it app /bin/bash
```
2、安装插件
```
$ su discourse 
$ cd /var/www/discourse 
$ RAILS_ENV=production bundle exec rake plugin:install repo=https://github.com/zhangml123/discourse_smart_captcha.git 
$ RAILS_ENV=production bundle exec rake assets:precompile;

```
###### 退出容器
3、重启容器
```
$ ./launcher restart app
```

##### 启动插件

###### 1、进入管理后台配置

管理员后台 》 设置 》 插件

###### 2、配置参数并启动插件

配置 app key, access key, access secret, remote ip 参数 （ 参数获取地址 https://promotion.aliyun.com/ntms/act/captchaIntroAndDemo.html）

勾选 discourse smart captcha 启动插件


