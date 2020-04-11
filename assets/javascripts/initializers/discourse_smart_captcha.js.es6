import { withPluginApi } from "discourse/lib/plugin-api";
import loadScript from "discourse/lib/load-script";
import { ajax } from "discourse/lib/ajax";
import discourseComputed from "discourse-common/utils/decorators";
import showModal from "discourse/lib/show-modal";
import EmberObject from "@ember/object";

function initialize(api) {
  const siteSettings = api.container.lookup("site-settings:main");
  
  if(siteSettings.discourse_smart_captcha) {
    loadScript("/plugins/discourse_smart_captcha/javascripts/quizCaptcha/0.0.1/index.js")
    loadScript("/plugins/discourse_smart_captcha/javascripts/nvc/1.1.112/guide.js")
    loadScript("/plugins/discourse_smart_captcha/javascripts/smartCaptcha/0.0.4/index.js")
    
    window.NVC_Opt = {
      appkey:siteSettings.app_key,
      scene:'ic_register',
      renderTo:'#captcha',
      trans: {"key1": "code0", "nvcCode":200},
      elements: [
          '//img.alicdn.com/tfs/TB17cwllsLJ8KJjy0FnXXcFDpXa-50-74.png',
          '//img.alicdn.com/tfs/TB17cwllsLJ8KJjy0FnXXcFDpXa-50-74.png'
      ], 
      bg_back_prepared: '//img.alicdn.com/tps/TB1skE5SFXXXXb3XXXXXXXXXXXX-100-80.png',
      bg_front: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGQAAABQCAMAAADY1yDdAAAABGdBTUEAALGPC/xhBQAAAAFzUkdCAK7OHOkAAAADUExURefk5w+ruswAAAAfSURBVFjD7cExAQAAAMKg9U9tCU+gAAAAAAAAAIC3AR+QAAFPlUGoAAAAAElFTkSuQmCC',
      obj_ok: '//img.alicdn.com/tfs/TB1rmyTltfJ8KJjy0FeXXXKEXXa-50-74.png',
      bg_back_pass: '//img.alicdn.com/tfs/TB1KDxCSVXXXXasXFXXXXXXXXXX-100-80.png',
      obj_error: '//img.alicdn.com/tfs/TB1q9yTltfJ8KJjy0FeXXXKEXXa-50-74.png',
      bg_back_fail: '//img.alicdn.com/tfs/TB1w2oOSFXXXXb4XpXXXXXXXXXX-100-80.png',
      upLang:{"cn":{
        _ggk_guide: "请摁住鼠标左键，刮出两面盾牌",
        _ggk_success: "恭喜您成功刮出盾牌<br/>继续下一步操作吧",
        _ggk_loading: "加载中",
        _ggk_fail: ['呀，盾牌不见了<br/>请', "javascript:noCaptcha.reset()", '再来一次', '或', "http://survey.taobao.com/survey/QgzQDdDd?token=%TOKEN", '反馈问题'],
        _ggk_action_timeout: ['我等得太久啦<br/>请', "javascript:noCaptcha.reset()", '再来一次', '或', "http://survey.taobao.com/survey/QgzQDdDd?token=%TOKEN", '反馈问题'],
        _ggk_net_err: ['网络实在不给力<br/>请', "javascript:noCaptcha.reset()", '再来一次', '或', "http://survey.taobao.com/survey/QgzQDdDd?token=%TOKEN", '反馈问题'],
        _ggk_too_fast: ['您刮得太快啦<br/>请', "javascript:noCaptcha.reset()", '再来一次', '或', "http://survey.taobao.com/survey/QgzQDdDd?token=%TOKEN", '反馈问题']
        }
      }
    }
    api.modifyClass('component:create-account', {
      didInsertElement(){
        this._super();
        const controller = showModal("create-account");      
        $("#discourse-modal").find(".modal-body").after("<div id='sc' style='padding:20px;width:300px;margin:0 auto' ></div>")
          loadScript("/plugins/discourse_smart_captcha/javascripts/smartCaptcha/0.0.4/index.js"
          ).then(() => {
              var ic = new smartCaptcha({
                renderTo: '#sc',
                width: 300,
                height: 42,
                default_txt: '点击按钮开始智能验证',
                success_txt: '验证成功',
                fail_txt: '验证失败，请在此点击按钮刷新',
                scaning_txt: '智能检测中',
                success: function(data) {
                  const userFields = [];
                  userFields.push(EmberObject.create({field:{id:"sessionId"},value:data.sessionId}))
                  userFields.push(EmberObject.create({field:{id:"token"},value:NVC_Opt.token}))
                  userFields.push(EmberObject.create({field:{id:"sig"},value:data.sig}))
                  controller.set("userFields", userFields); 
                  controller.set("captchaVerified", true);               
                
                },
                fail: function(data) {
                 
                  controller.set("captchaVerified", false);
                  console.log('ic error');
                }
            });
            ic.init();
            console.log("#modal-alert")
            console.log($("#modal-alert"))
            $("#modal-alert").bind("DOMNodeInserted", function(){

              console.log("changes1111")
            })
            controller.set("ic",ic)

          });
      }
    })
    api.modifyClass('controller:create-account', {
      captchaVerified:false,
      ic:null,
     @discourseComputed(
        "passwordRequired",
        "nameValidation.failed",
        "emailValidation.failed",
        "usernameValidation.failed",
        "passwordValidation.failed",
        "userFieldsValidation.failed",
        "formSubmitted",
        "inviteCode",
        "captchaVerified",
        "rejectedEmails.[]"
      )
      submitDisabled() {
        console.log("submitDisabled.formSubmitted")
        console.log("this.formSubmitted 1111111= " + this.formSubmitted)
        console.log(this.ic)

        if (this.rejectedEmails.length > 0 ){
          console.log("rejectedEmails.length > 0")
          console.log($("#modal-alert").html())
          this.ic.reset();
          this.rejectedEmails = []
        }
        if (!this.captchaVerified) return true;
        if (this.formSubmitted) return true;
        if (this.get("nameValidation.failed")) return true;
        if (this.get("emailValidation.failed")) return true;
        if (this.get("usernameValidation.failed") && this.usernameRequired)
          return true;
        if (this.get("passwordValidation.failed") && this.passwordRequired)
          return true;
        if (this.get("userFieldsValidation.failed")) return true;
        if (this.requireInviteCode && !this.inviteCode) return true;
        return false;
      },
      
    })

  }
}

export default {
  name: "discourse_smart_captcha",
  initialize() {
    withPluginApi("0.8.7", initialize);
  }
};
